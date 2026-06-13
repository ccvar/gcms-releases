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

如果服务器已经有域名解析，并且希望自动配置 HTTPS 入口，可以分两步执行：

```sh
# 1. 只安装 Caddy
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install-caddy.sh | sudo sh

# 2. 把已安装的 GCMS 接入 Caddy
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/setup-caddy.sh | sudo env DOMAIN=example.com WWW_REDIRECT=1 GCMS_HOME=/opt/gcms sh
```

也可以在安装 GCMS 时顺手配置 Caddy：

```sh
curl -fsSL https://raw.githubusercontent.com/ccvar/gcms-releases/main/install.sh | sudo env ENABLE_CADDY=1 DOMAIN=example.com WWW_REDIRECT=1 sh
```

`setup-caddy.sh` 会自动检测：

- `GCMS_HOME`，不传时依次尝试当前目录、`/opt/gcms`、`$HOME/gcms`
- `shared/cms.conf` 中的 `ADDR` 和 `BASE_URL`
- 未传 `DOMAIN` 时，会尝试从 `BASE_URL` 推断域名
- `WWW_REDIRECT=1` 时，会把 `www.example.com` 永久跳转到 `example.com`
- 如果没有安全的本地监听地址，会把 GCMS 改成 `127.0.0.1:8080`

这些脚本会：

- 要求在 Linux root 用户下执行
- 按需安装 Caddy（支持常见的 apt / dnf / pacman 系统；如果已安装则直接复用）
- 写入 `ADDR=127.0.0.1:8080` 或检测到的本地监听地址
- 写入 `BASE_URL=https://你的域名`
- 写入 `/etc/caddy/conf.d/gcms.caddy`
- 在 `/etc/caddy/Caddyfile` 中追加 `import /etc/caddy/conf.d/*.caddy`
- 校验 Caddy 配置并 reload/restart Caddy

默认生成的站点配置会采用 GCMS 推荐的 Caddyfile 结构：

```caddyfile
www.example.com {
    redir https://example.com{uri} permanent
}

example.com {
    encode zstd gzip

    header /assets/* Cache-Control "public, max-age=31536000, immutable"
    header /uploads/* Cache-Control "public, max-age=2592000"

    reverse_proxy 127.0.0.1:8080
}
```

请提前确认：

- `DOMAIN` 只填写域名，不要带 `https://` 或路径
- `DOMAIN=example.com` 是主域；`WWW_REDIRECT=1` 会自动处理 `www.example.com`
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
