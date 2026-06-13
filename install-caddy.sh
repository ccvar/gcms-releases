#!/usr/bin/env sh
# Install Caddy for GCMS deployments.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install-caddy.sh | sudo sh

set -eu

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

need_linux_root() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  [ "$os" = "linux" ] || fail "Caddy 自动安装暂只支持 Linux。其他系统请参考 Caddy 官方文档手动安装。"
  [ "$(id -u)" = "0" ] || fail "安装 Caddy 需要 root 权限。请使用 sudo sh 或切换到 root 后执行。"
}

install_caddy_apt() {
  info "安装 Caddy（Debian/Ubuntu/Raspbian 官方 apt 源）"
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
  if dnf -y install dnf5-plugins; then
    :
  else
    dnf -y install dnf-plugins-core
  fi
  dnf -y copr enable @caddy/caddy
  dnf -y install caddy
}

install_caddy_pacman() {
  info "安装 Caddy（Arch/Manjaro pacman）"
  pacman -Syu --noconfirm caddy
}

start_caddy_service() {
  if command -v systemctl >/dev/null 2>&1 &&
    [ -d /run/systemd/system ] &&
    systemctl list-unit-files caddy.service --no-legend 2>/dev/null | grep -q '^caddy\.service'; then
    systemctl enable --now caddy
    ok "Caddy systemd 服务已启用"
    return
  fi
  warn "未检测到可用的 caddy systemd 服务，已完成安装但未自动启动服务。"
}

main() {
  need_linux_root

  if command -v caddy >/dev/null 2>&1; then
    ok "已检测到 Caddy：$(caddy version 2>/dev/null || printf 'installed')"
    start_caddy_service
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    install_caddy_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_caddy_dnf
  elif command -v pacman >/dev/null 2>&1; then
    install_caddy_pacman
  else
    fail "未找到支持的包管理器。请参考 Caddy 官方文档手动安装。"
  fi

  command -v caddy >/dev/null 2>&1 || fail "Caddy 安装后仍不可用，请检查系统包管理器输出。"
  ok "Caddy 已安装：$(caddy version 2>/dev/null || printf 'installed')"
  start_caddy_service
}

main "$@"
