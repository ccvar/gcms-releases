# GCMS Releases

This public repository stores compiled GCMS release assets, checksums, and update manifests. The source repository remains private.

## 一键安装

Linux / macOS 可直接执行：

```sh
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | sh
```

默认安装目录：

- root 用户：`/opt/gcms`
- 普通用户：`$HOME/gcms`

常用自定义方式：

```sh
# 指定安装目录
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | env GCMS_HOME=/opt/gcms sh

# 指定端口和站点地址
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | env ADDR=:8080 BASE_URL=https://cms.example.com sh

# 只安装不启动
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | env GCMS_START=0 sh

# 指定版本
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | env GCMS_VERSION=v1.0.11 sh
```

## 一键安装并配置 Caddy

如果服务器已经有域名解析，并且希望自动配置 HTTPS 入口，可以显式开启 Caddy 模式：

```sh
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | env ENABLE_CADDY=1 DOMAIN=cms.example.com sh
```

如果当前不是 root 用户：

```sh
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | sudo env ENABLE_CADDY=1 DOMAIN=cms.example.com sh
```

Caddy 模式会：

- 要求在 Linux root 用户下执行
- 自动安装 Caddy（支持常见的 apt / dnf / pacman 系统；如果已安装则直接复用）
- 默认让 GCMS 监听 `127.0.0.1:8080`
- 写入 `BASE_URL=https://你的域名`
- 写入 `/etc/caddy/conf.d/gcms.caddy`
- 在 `/etc/caddy/Caddyfile` 中追加 `import /etc/caddy/conf.d/*.caddy`
- 校验 Caddy 配置并 reload/restart Caddy

请提前确认：

- `DOMAIN` 只填写域名，不要带 `https://` 或路径
- 域名已经解析到当前服务器
- 防火墙和云厂商安全组已放行 `80` / `443`
- 如果服务器已有复杂 Caddy 配置，建议先备份 `/etc/caddy/Caddyfile`

安装完成后：

```sh
cd /opt/gcms    # root 默认目录；普通用户默认是 ~/gcms
./scripts/cms.sh status
./scripts/cms.sh logs
./scripts/cms.sh upgrade
```

首次登录默认账号为 `admin / admin123`，登录后请尽快修改密码。
