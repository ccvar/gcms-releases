#!/usr/bin/env sh
# Configure Caddy as the public HTTPS entry for an installed GCMS directory.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/setup-caddy.sh | sudo env DOMAIN=cms.example.com GCMS_HOME=/opt/gcms sh

set -eu

RELEASE_REPO=${GCMS_RELEASE_REPO:-ccvar/gcms-releases}
INSTALL_CADDY_URL=${GCMS_INSTALL_CADDY_URL:-https://raw.githubusercontent.com/$RELEASE_REPO/main/install-caddy.sh}
CADDYFILE=${GCMS_CADDYFILE:-/etc/caddy/Caddyfile}
CADDY_CONF_DIR=${GCMS_CADDY_CONF_DIR:-/etc/caddy/conf.d}
CADDY_SITE_FILE=${GCMS_CADDY_SITE_FILE:-$CADDY_CONF_DIR/gcms.caddy}
SITE_DOMAIN=${DOMAIN:-${GCMS_DOMAIN:-}}
SKIP_CADDY_INSTALL=${GCMS_SKIP_CADDY_INSTALL:-0}

if [ -t 1 ]; then
  C_OK='\033[32m'
  C_ERR='\033[31m'
  C_DIM='\033[2m'
  C_WARN='\033[33m'
  C_0='\033[0m'
else
  C_OK=
  C_ERR=
  C_DIM=
  C_WARN=
  C_0=
fi

info() { printf "%b\n" "${C_DIM}» $*${C_0}"; }
ok() { printf "%b\n" "${C_OK}✓ $*${C_0}"; }
warn() { printf "%b\n" "${C_WARN}! $*${C_0}"; }
err() { printf "%b\n" "${C_ERR}✗ $*${C_0}" >&2; }
fail() { err "$*"; exit 1; }

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

download_file() {
  url=$1
  dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url"
  else
    fail "需要 curl 或 wget 下载文件"
  fi
}

need_linux_root() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  [ "$os" = "linux" ] || fail "Caddy 配置脚本暂只支持 Linux。其他系统请手动配置 Caddy。"
  [ "$(id -u)" = "0" ] || fail "配置 Caddy 需要 root 权限。请使用 sudo env DOMAIN=... sh。"
}

is_standard_gcms() {
  dir=$1
  [ -x "$dir/scripts/cms.sh" ] &&
    [ -e "$dir/current" ] &&
    [ -d "$dir/releases" ] &&
    [ -d "$dir/shared" ]
}

detect_gcms_home() {
  if [ -n "${GCMS_HOME:-}" ]; then
    is_standard_gcms "$GCMS_HOME" || fail "GCMS_HOME 不是标准 GCMS 目录：$GCMS_HOME"
    printf '%s' "$GCMS_HOME"
    return
  fi

  for dir in "$(pwd)" /opt/gcms "${HOME:-}/gcms"; do
    [ -n "$dir" ] || continue
    if [ -d "$dir" ] && is_standard_gcms "$dir"; then
      printf '%s' "$dir"
      return
    fi
  done

  fail "未找到 GCMS 标准目录。请传入 GCMS_HOME=/opt/gcms。"
}

conf_value() {
  conf=$1
  key=$2
  [ -f "$conf" ] || return 0
  awk -F= -v key="$key" '
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      split(line, parts, "=")
      k=parts[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == key) {
        sub(/^[^=]*=/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  ' "$conf"
}

set_conf_value() {
  conf=$1
  key=$2
  value=$3
  tmp="${conf}.tmp.$$"
  mkdir -p "$(dirname "$conf")"
  if [ -f "$conf" ] && grep -q "^${key}=" "$conf"; then
    awk -v k="$key" -v v="$value" 'BEGIN{done=0} $0 ~ "^" k "=" { print k "=" v; done=1; next } { print } END{ if (!done) print k "=" v }' "$conf" > "$tmp"
  else
    if [ -f "$conf" ]; then
      cp "$conf" "$tmp"
    else
      : > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$conf"
}

domain_from_base_url() {
  url=$1
  case "$url" in
    http://*|https://*)
      host=${url#http://}
      host=${host#https://}
      host=${host%%/*}
      printf '%s' "$host"
      ;;
  esac
}

validate_domain() {
  domain=$1
  [ -n "$domain" ] || fail "需要传入 DOMAIN，例如：DOMAIN=cms.example.com"
  case "$domain" in
    http://*|https://*|*/*|*' '*)
      fail "DOMAIN 只填写域名，不要带 http(s)://、路径或空格，例如：DOMAIN=cms.example.com"
      ;;
    \**)
      fail "一键 Caddy 配置暂不支持通配符域名。请手动配置 DNS-01 后再接入 Caddy。"
      ;;
  esac
}

normalize_backend_addr() {
  addr=${1:-}
  [ -n "$addr" ] || addr=127.0.0.1:8080
  case "$addr" in
    :*) printf '127.0.0.1%s' "$addr" ;;
    0.0.0.0:*) printf '127.0.0.1:%s' "${addr##*:}" ;;
    '[::]'*) printf '127.0.0.1:%s' "${addr##*:}" ;;
    *) printf '%s' "$addr" ;;
  esac
}

ensure_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    ok "已检测到 Caddy：$(caddy version 2>/dev/null || printf 'installed')"
    return
  fi

  if is_true "$SKIP_CADDY_INSTALL"; then
    fail "未检测到 caddy 命令。请先运行 install-caddy.sh，或取消 GCMS_SKIP_CADDY_INSTALL。"
  fi

  info "未检测到 Caddy，先安装 Caddy"
  work=$(mktemp -d 2>/dev/null || mktemp -d -t gcms-caddy-install)
  trap 'rm -rf "$work"' EXIT INT TERM
  installer="$work/install-caddy.sh"
  download_file "$INSTALL_CADDY_URL" "$installer"
  sh "$installer"
  command -v caddy >/dev/null 2>&1 || fail "Caddy 安装后仍不可用，请检查安装输出。"
}

ensure_caddy_import() {
  mkdir -p "$(dirname "$CADDYFILE")" "$CADDY_CONF_DIR"
  [ -f "$CADDYFILE" ] || : > "$CADDYFILE"

  import_line="import $CADDY_CONF_DIR/*.caddy"
  if ! grep -Fxq "$import_line" "$CADDYFILE"; then
    {
      printf '\n'
      printf '# GCMS installer: load site snippets managed under %s/\n' "$CADDY_CONF_DIR"
      printf '%s\n' "$import_line"
    } >> "$CADDYFILE"
  fi
}

write_caddy_site() {
  domain=$1
  backend=$2
  tmp="${CADDY_SITE_FILE}.tmp.$$"
  mkdir -p "$(dirname "$CADDY_SITE_FILE")"
  {
    printf '# Managed by GCMS setup-caddy.sh. Re-run the script to update.\n'
    printf '%s {\n' "$domain"
    printf '    encode gzip\n'
    printf '    reverse_proxy %s\n' "$backend"
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$CADDY_SITE_FILE"
  chmod 0644 "$CADDY_SITE_FILE"
  ok "已写入 Caddy 站点配置：$CADDY_SITE_FILE（反代到 $backend）"
}

reload_caddy() {
  if command -v systemctl >/dev/null 2>&1 &&
    [ -d /run/systemd/system ] &&
    systemctl list-unit-files caddy.service --no-legend 2>/dev/null | grep -q '^caddy\.service'; then
    systemctl enable --now caddy
    systemctl reload caddy || systemctl restart caddy
    return
  fi

  if caddy reload --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
    return
  fi
  caddy start --config "$CADDYFILE" --adapter caddyfile
}

main() {
  need_linux_root
  root=$(detect_gcms_home)
  conf="$root/shared/cms.conf"
  [ -f "$conf" ] || fail "缺少 GCMS 配置文件：$conf"

  conf_backup="$conf.gcms-caddy-backup-$(date '+%Y%m%d%H%M%S')"
  cp "$conf" "$conf_backup"

  base_url=${BASE_URL:-$(conf_value "$conf" BASE_URL)}
  if [ -z "$SITE_DOMAIN" ] && [ -n "$base_url" ]; then
    SITE_DOMAIN=$(domain_from_base_url "$base_url")
  fi
  validate_domain "$SITE_DOMAIN"

  backend=$(normalize_backend_addr "${ADDR:-$(conf_value "$conf" ADDR)}")
  site_url=${BASE_URL:-https://$SITE_DOMAIN}

  set_conf_value "$conf" ADDR "$backend"
  set_conf_value "$conf" BASE_URL "$site_url"
  ok "已更新 GCMS 配置：ADDR=$backend，BASE_URL=$site_url"

  ensure_caddy

  stamp=$(date '+%Y%m%d%H%M%S')
  caddy_backup="$CADDYFILE.gcms-backup-$stamp"
  site_backup="$CADDY_SITE_FILE.gcms-backup-$stamp"
  had_caddyfile=0
  had_sitefile=0
  if [ -f "$CADDYFILE" ]; then
    cp "$CADDYFILE" "$caddy_backup"
    had_caddyfile=1
  fi
  if [ -f "$CADDY_SITE_FILE" ]; then
    cp "$CADDY_SITE_FILE" "$site_backup"
    had_sitefile=1
  fi

  ensure_caddy_import
  write_caddy_site "$SITE_DOMAIN" "$backend"

  info "校验 Caddy 配置"
  if ! caddy validate --config "$CADDYFILE" --adapter caddyfile; then
    cp "$conf_backup" "$conf"
    if [ "$had_caddyfile" = "1" ]; then
      cp "$caddy_backup" "$CADDYFILE"
    else
      rm -f "$CADDYFILE"
    fi
    if [ "$had_sitefile" = "1" ]; then
      cp "$site_backup" "$CADDY_SITE_FILE"
    else
      rm -f "$CADDY_SITE_FILE"
    fi
    fail "Caddy 配置校验失败，已回滚 GCMS 与 Caddy 配置。"
  fi

  info "重载 Caddy"
  reload_caddy || fail "Caddy 重载失败。请检查 systemctl status caddy 或 Caddy 日志。"
  ok "Caddy 已配置：https://$SITE_DOMAIN → $backend"
  warn "请确认域名 $SITE_DOMAIN 已解析到这台服务器，并且防火墙放行 80/443。"
}

main "$@"
