#!/usr/bin/env sh
# GCMS one-line installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | sh
#
# Optional environment variables:
#   GCMS_HOME=/opt/gcms             Install directory. Default: /opt/gcms as root, $HOME/gcms otherwise.
#   GCMS_VERSION=v1.0.11            Install/upgrade a specific release tag. Default: latest release.
#   GCMS_RELEASE_REPO=ccvar/gcms-releases
#   GCMS_UPDATE_URL=https://.../manifest.json
#   GCMS_START=0                    Install only, do not start the service.
#   ADDR=:8080                      Listen address written to shared/cms.conf.
#   BASE_URL=https://example.com    Public site URL written to shared/cms.conf.
#   ENABLE_CADDY=1 DOMAIN=example.com
#                                    Install/configure Caddy on Linux and proxy HTTPS to GCMS.

set -eu

RELEASE_REPO=${GCMS_RELEASE_REPO:-ccvar/gcms-releases}
VERSION=${GCMS_VERSION:-}
START_AFTER_INSTALL=${GCMS_START:-1}
ENABLE_CADDY=${ENABLE_CADDY:-${GCMS_ENABLE_CADDY:-0}}
SITE_DOMAIN=${DOMAIN:-${GCMS_DOMAIN:-}}
CADDYFILE=${GCMS_CADDYFILE:-/etc/caddy/Caddyfile}
CADDY_CONF_DIR=${GCMS_CADDY_CONF_DIR:-/etc/caddy/conf.d}

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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少必要命令：$1"
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

manifest_url() {
  if [ -n "${GCMS_UPDATE_URL:-}" ]; then
    printf '%s' "$GCMS_UPDATE_URL"
    return
  fi
  if [ -n "$VERSION" ]; then
    printf 'https://github.com/%s/releases/download/%s/manifest.json' "$RELEASE_REPO" "$VERSION"
    return
  fi
  printf 'https://github.com/%s/releases/latest/download/manifest.json' "$RELEASE_REPO"
}

detect_platform() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  case "$os" in
    linux|darwin) ;;
    *) fail "暂不支持当前系统：$os。请到 https://github.com/$RELEASE_REPO/releases 手动下载对应发布包。" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) fail "暂不支持当前 CPU 架构：$arch。请到 https://github.com/$RELEASE_REPO/releases 手动下载对应发布包。" ;;
  esac

  printf '%s/%s' "$os" "$arch"
}

sha256_file() {
  file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    return 1
  fi
}

manifest_asset_info() {
  manifest=$1
  goos=$2
  goarch=$3
  wanted=$4
  python3 - "$manifest" "$goos" "$goarch" "$wanted" <<'PY'
import json
import sys

manifest_path, goos, goarch, wanted = sys.argv[1:5]
with open(manifest_path, "r", encoding="utf-8") as f:
    data = json.load(f)

version = data.get("version", "")
if wanted and version != wanted:
    raise SystemExit("更新清单版本是 {}，不是指定的 {}".format(version or "unknown", wanted))

asset = None
for item in data.get("assets", []):
    if item.get("os") == goos and item.get("arch") == goarch and str(item.get("name", "")).endswith(".tar.gz"):
        asset = item
        break

if not asset:
    raise SystemExit("更新清单中没有匹配平台 {}/{} 的 tar.gz 发布包".format(goos, goarch))

print(version)
print(asset.get("name", ""))
print(asset.get("url", ""))
print(asset.get("sha256", ""))
PY
}

is_standard_install() {
  dir=$1
  [ -x "$dir/scripts/cms.sh" ] &&
    [ -e "$dir/current" ] &&
    [ -d "$dir/releases" ] &&
    [ -d "$dir/shared" ]
}

is_empty_dir() {
  dir=$1
  [ -d "$dir" ] || return 0
  [ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

default_home() {
  if [ "$(id -u)" = "0" ]; then
    printf '/opt/gcms'
  else
    home=${HOME:-}
    [ -n "$home" ] || fail "无法确定 HOME，请设置 GCMS_HOME=/path/to/gcms 后重试"
    printf '%s/gcms' "$home"
  fi
}

set_conf_value() {
  conf=$1
  key=$2
  value=$3
  tmp="${conf}.tmp.$$"
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

configure_install() {
  root=$1
  conf="$root/shared/cms.conf"
  [ -f "$conf" ] || return 0
  [ -n "${ADDR:-}" ] && set_conf_value "$conf" ADDR "$ADDR"
  [ -n "${BASE_URL:-}" ] && set_conf_value "$conf" BASE_URL "$BASE_URL"
  return 0
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

caddy_enabled() {
  is_true "$ENABLE_CADDY"
}

prepare_caddy_env() {
  goos=$1
  caddy_enabled || return 0

  [ "$goos" = "linux" ] || fail "Caddy 自动安装与系统服务配置暂只支持 Linux。其他系统请手动安装 Caddy 后配置反向代理。"
  [ "$(id -u)" = "0" ] || fail "ENABLE_CADDY=1 需要 root 权限：脚本要安装 Caddy 并写入 /etc/caddy。"
  [ -n "$SITE_DOMAIN" ] || fail "启用 Caddy 时需要传入 DOMAIN，例如：ENABLE_CADDY=1 DOMAIN=cms.example.com"

  case "$SITE_DOMAIN" in
    http://*|https://*|*/*|*' '*)
      fail "DOMAIN 只填写域名，不要带 http(s)://、路径或空格，例如：DOMAIN=cms.example.com"
      ;;
    \**)
      fail "一键 Caddy 模式暂不支持通配符域名。请手动配置 DNS-01 后再接入 Caddy。"
      ;;
  esac

  if [ -z "${ADDR:-}" ]; then
    ADDR=127.0.0.1:8080
  fi
  if [ -z "${BASE_URL:-}" ]; then
    BASE_URL="https://$SITE_DOMAIN"
  fi
}

caddy_backend() {
  addr=${ADDR:-127.0.0.1:8080}
  case "$addr" in
    :*) printf '127.0.0.1%s' "$addr" ;;
    0.0.0.0:*) printf '127.0.0.1:%s' "${addr##*:}" ;;
    '[::]'*) printf '127.0.0.1:%s' "${addr##*:}" ;;
    *) printf '%s' "$addr" ;;
  esac
}

install_caddy_apt() {
  info "安装 Caddy（Debian/Ubuntu 官方 apt 源）"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  tmp_key="/tmp/caddy-stable-gpg.$$"
  curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o "$tmp_key"
  gpg --dearmor < "$tmp_key" > /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  rm -f "$tmp_key"
  curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' -o /etc/apt/sources.list.d/caddy-stable.list
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
}

install_caddy_dnf() {
  info "安装 Caddy（Fedora/RHEL/CentOS COPR）"
  dnf -y install dnf5-plugins || dnf -y install dnf-plugins-core
  dnf -y copr enable @caddy/caddy
  dnf -y install caddy
}

install_caddy_pacman() {
  info "安装 Caddy（Arch/Manjaro pacman）"
  pacman -Sy --noconfirm caddy
}

install_caddy_if_needed() {
  if command -v caddy >/dev/null 2>&1; then
    ok "已检测到 Caddy：$(caddy version 2>/dev/null || printf 'installed')"
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    install_caddy_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_caddy_dnf
  elif command -v pacman >/dev/null 2>&1; then
    install_caddy_pacman
  else
    fail "未找到支持的包管理器。请先手动安装 Caddy，再重新执行 ENABLE_CADDY=1 DOMAIN=$SITE_DOMAIN。"
  fi

  command -v caddy >/dev/null 2>&1 || fail "Caddy 安装后仍不可用，请检查系统包管理器输出。"
}

ensure_caddy_import() {
  caddyfile=$1
  mkdir -p "$(dirname "$caddyfile")" "$CADDY_CONF_DIR"
  [ -f "$caddyfile" ] || : > "$caddyfile"

  import_line="import $CADDY_CONF_DIR/*.caddy"
  if ! grep -Fxq "$import_line" "$caddyfile"; then
    {
      printf '\n'
      printf '# GCMS installer: load site snippets managed under %s/\n' "$CADDY_CONF_DIR"
      printf '%s\n' "$import_line"
    } >> "$caddyfile"
  fi
}

write_caddy_site() {
  sitefile="$CADDY_CONF_DIR/gcms.caddy"
  backend=$(caddy_backend)
  tmp="${sitefile}.tmp.$$"
  {
    printf '# Managed by GCMS installer. Re-run install.sh with ENABLE_CADDY=1 to update.\n'
    printf '%s {\n' "$SITE_DOMAIN"
    printf '    encode gzip\n'
    printf '    reverse_proxy %s\n' "$backend"
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$sitefile"
  chmod 0644 "$sitefile"
  ok "已写入 Caddy 站点配置：$sitefile（反代到 $backend）"
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

setup_caddy() {
  caddy_enabled || return 0

  install_caddy_if_needed

  stamp=$(date '+%Y%m%d%H%M%S')
  backup="$CADDYFILE.gcms-backup-$stamp"
  original_exists=0
  if [ -f "$CADDYFILE" ]; then
    cp "$CADDYFILE" "$backup"
    original_exists=1
  fi

  ensure_caddy_import "$CADDYFILE"
  write_caddy_site

  info "校验 Caddy 配置"
  if ! caddy validate --config "$CADDYFILE" --adapter caddyfile; then
    rm -f "$CADDY_CONF_DIR/gcms.caddy"
    if [ "$original_exists" = "1" ]; then
      cp "$backup" "$CADDYFILE"
    else
      rm -f "$CADDYFILE"
    fi
    fail "Caddy 配置校验失败，已回滚 /etc/caddy 配置。"
  fi

  info "重载 Caddy"
  reload_caddy || fail "Caddy 重载失败。请检查 systemctl status caddy 或 Caddy 日志。"
  ok "Caddy 已配置：https://$SITE_DOMAIN → $(caddy_backend)"
  warn "请确认域名 $SITE_DOMAIN 已解析到这台服务器，并且防火墙放行 80/443。"
}

base_url_hint() {
  if [ -n "${BASE_URL:-}" ]; then
    printf '%s' "$BASE_URL"
    return
  fi
  addr=${ADDR:-:8080}
  case "$addr" in
    :*) printf 'http://localhost%s' "$addr" ;;
    0.0.0.0:*) printf 'http://localhost:%s' "${addr##*:}" ;;
    *) printf 'http://%s' "$addr" ;;
  esac
}

print_done() {
  root=$1
  url=$(base_url_hint)
  ok "GCMS 已安装到：$root"
  printf '\n'
  printf '常用命令：\n'
  printf '  cd %s\n' "$root"
  printf '  ./scripts/cms.sh status\n'
  printf '  ./scripts/cms.sh logs\n'
  printf '  ./scripts/cms.sh restart\n'
  printf '  ./scripts/cms.sh upgrade\n'
  printf '\n'
  printf '访问地址：\n'
  printf '  前台：%s\n' "$url"
  printf '  后台：%s/admin\n' "$url"
  if caddy_enabled; then
    printf '  Caddy：%s → %s\n' "$SITE_DOMAIN" "$(caddy_backend)"
  fi
  printf '\n'
  warn '首次登录默认账号：admin / admin123，登录后请尽快修改密码。'
}

run_upgrade_if_standard() {
  root=$1
  info "检测到已有标准 GCMS 目录，改为执行升级：$root"
  chmod +x "$root/scripts/cms.sh" 2>/dev/null || true
  configure_install "$root"
  if [ -n "$VERSION" ]; then
    (cd "$root" && ./scripts/cms.sh upgrade "$VERSION")
  else
    (cd "$root" && ./scripts/cms.sh upgrade)
  fi
  setup_caddy
  if [ "$START_AFTER_INSTALL" != "0" ]; then
    (cd "$root" && ./scripts/cms.sh start)
  fi
  print_done "$root"
}

main() {
  need_cmd uname
  need_cmd tar
  need_cmd python3
  need_cmd awk
  need_cmd find

  root=${GCMS_HOME:-$(default_home)}
  platform=$(detect_platform)
  goos=${platform%/*}
  goarch=${platform#*/}
  prepare_caddy_env "$goos"

  if [ -d "$root" ] && is_standard_install "$root"; then
    run_upgrade_if_standard "$root"
    return
  fi

  if [ -e "$root" ] && ! is_empty_dir "$root"; then
    fail "安装目录已存在且不是空目录：$root。请设置 GCMS_HOME=/new/path，或先清理该目录。"
  fi

  work=$(mktemp -d 2>/dev/null || mktemp -d -t gcms-install)
  trap 'rm -rf "$work"' EXIT INT TERM

  murl=$(manifest_url)
  manifest="$work/manifest.json"
  info "下载更新清单：$murl"
  download_file "$murl" "$manifest" || fail "下载更新清单失败"

  parsed=$(manifest_asset_info "$manifest" "$goos" "$goarch" "$VERSION" 2>"$work/manifest.err") || {
    fail "$(cat "$work/manifest.err")"
  }
  release_version=$(printf '%s\n' "$parsed" | sed -n '1p')
  asset_name=$(printf '%s\n' "$parsed" | sed -n '2p')
  asset_url=$(printf '%s\n' "$parsed" | sed -n '3p')
  asset_sha=$(printf '%s\n' "$parsed" | sed -n '4p')

  [ -n "$release_version" ] || fail "更新清单缺少 version"
  [ -n "$asset_name" ] || fail "更新清单缺少发布包名称"
  [ -n "$asset_url" ] || fail "更新清单缺少发布包下载地址"
  [ -n "$asset_sha" ] || fail "更新清单缺少发布包 SHA256"

  pkg="$work/$asset_name"
  info "下载发布包：$asset_name"
  download_file "$asset_url" "$pkg" || fail "下载发布包失败：$asset_name"

  info "校验 SHA256"
  actual_sha=$(sha256_file "$pkg") || fail "缺少 SHA256 工具，请安装 sha256sum、shasum 或 openssl"
  [ "$actual_sha" = "$asset_sha" ] || fail "SHA256 不匹配，已停止安装"
  ok "SHA256 校验通过"

  extract_dir="$work/extract"
  mkdir -p "$extract_dir"
  info "解压发布包"
  LC_ALL=C tar -xzf "$pkg" -C "$extract_dir" || fail "解压发布包失败"
  package_root=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$package_root" ] || fail "发布包结构异常：缺少根目录"
  [ -x "$package_root/scripts/cms.sh" ] || fail "发布包结构异常：缺少 scripts/cms.sh"
  [ -e "$package_root/current" ] || fail "发布包结构异常：缺少 current"
  [ -d "$package_root/shared" ] || fail "发布包结构异常：缺少 shared"

  mkdir -p "$root"
  info "安装到：$root"
  cp -R "$package_root"/. "$root"/
  chmod +x "$root/scripts/cms.sh" 2>/dev/null || true
  chmod +x "$root/current/bin/cms" 2>/dev/null || true
  configure_install "$root"
  setup_caddy

  if [ "$START_AFTER_INSTALL" = "0" ]; then
    ok "已安装 GCMS $release_version（未自动启动）"
  else
    info "启动服务"
    (cd "$root" && ./scripts/cms.sh start)
  fi

  print_done "$root"
}

main "$@"
