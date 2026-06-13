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

安装完成后：

```sh
cd /opt/gcms    # root 默认目录；普通用户默认是 ~/gcms
./scripts/cms.sh status
./scripts/cms.sh logs
./scripts/cms.sh upgrade
```

首次登录默认账号为 `admin / admin123`，登录后请尽快修改密码。
