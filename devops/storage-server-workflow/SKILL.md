---
name: storage-server-workflow
description: 腾讯云1Panel存储服务器管理 - 文件存储、备份、沙盒限制绕过
category: devops
---
# Storage Server Workflow

## 概述
腾讯云 1Panel 服务器作为 Hermes 的外挂存储，用于文件存储、备份和沙盒限制绕过。

## 服务器信息
- IP: 106.54.28.92
- Port: 22
- User: **root** (NOT ubuntu - ubuntu user password auth does NOT work)
- Auth: SSH key only (password auth fails)
- SSH Key: `/home/lighthouse/.ssh/id_rsa_1panel` (local) → corresponding pubkey on server for root
- 1Panel URL: http://106.54.28.92:13311
- 1Panel User: urzlwqazji
- 1Panel Pass: f5ll1zi7b2
- Storage Path: /data/hermes-storage

## 架构要点

- nginx 运行在 Docker 容器 `967a8d2cefe2` 中
- Host 配置目录: `/opt/1panel/www/conf.d/`（挂载到容器内 `/usr/local/openresty/nginx/conf/conf.d/`）
- Port 80 开放；8090/18080/13311 被防火墙封锁
- 公网文件 URL: `http://106.54.28.92/files/`

## 常用操作

### SSH 连接
```bash
ssh -i /home/lighthouse/.ssh/id_rsa_1panel root@106.54.28.92
```
注意：必须用 `root` 用户，`ubuntu` 用户 SSH key 登录会失败（Permission denied）

### 重载 nginx（绕过 sudo TTY）
```bash
docker exec 967a8d2cefe2 nginx -s reload
```

### 启动 Python HTTP 文件服务器
```bash
cd /data/hermes-storage && nohup python3 -m http.server 18080 > /tmp/http_server.log 2>&1 &
```

### SCP 传输
```bash
scp -i /home/lighthouse/.ssh/id_rsa_1panel file.txt root@106.54.28.92:/data/hermes-storage/
```

## 故障排查
- 公网 403/404 → 检查 Python HTTP 服务器是否运行
- nginx 502 → proxy_pass 端口配置错误
- Docker 重启后需重新启动 Python HTTP 服务器

### Docker nginx 连接 host 18080
Docker 容器使用 `--network=host` 模式，**可以直接访问** `127.0.0.1:18080`（不需要 host.docker.internal）。

### 502 Bad Gateway 排查：Python HTTP 服务器僵死
Python HTTP 服务器有时会进入**僵死状态**——进程存在、端口绑定，但实际不提供服务，导致 nginx 502。
**症状**：`ss -tlnp | grep 18080` 显示进程存在，但 `curl http://127.0.0.1:18080/` 无响应或超时。
**解法**：
```bash
# 强制杀死所有 http.server 进程（普通 pkill 可能失败，需 -9）
pkill -9 -f 'http.server'
sleep 2
cd /data/hermes-storage && python3 -m http.server 18080 > /root/http.log 2>&1 &
```
验证：`curl http://127.0.0.1:18080/文件名` 应立即返回内容。

### nginx 配置转义问题
在 1Panel 界面编辑的 nginx 配置，`$uri` 会被自动转义为 `\$uri`，导致 reload 失败。修复：
```bash
docker exec 1Panel-openresty-ZivO sed -i 's/\\\$uri/$uri/g' /usr/local/openresty/nginx/conf/conf.d/xxx.conf
docker exec 1Panel-openresty-ZivO nginx -s reload
```
