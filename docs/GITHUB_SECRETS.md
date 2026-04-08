# GitHub Secrets 清单

在 **ai-frontend**、**ai-backend** 仓库（以及可选的 **deploy-infra** 组织级）中配置以下 Secrets。不要在仓库中提交明文。

| Secret | 说明 |
|--------|------|
| `ACR_USERNAME` | 阿里云容器镜像服务登录用户名 |
| `ACR_PASSWORD` | 阿里云容器镜像服务登录密码（或具有推送权限的临时令牌） |
| `SSH_HOST` | ECS 公网 IP 或主机名（SSH 目标） |
| `SSH_USERNAME` | SSH 登录用户（通常为 `root` 或具有 docker 权限的用户） |
| `SSH_KEY` | SSH 私钥全文（OpenSSH 格式，`-----BEGIN ... PRIVATE KEY-----`） |
| `DEPLOY_ROOT` | （可选）服务器上本仓库克隆路径，默认 `~/deploy-infra` |

可选：若按环境拆分主机，可在 workflow 中自行改为 `SSH_HOST_PROD` / `SSH_HOST_DEV` 等表达式（需同步修改 `templates/github/*.yml`）。

## 服务器侧要求

- 已安装 Docker Engine 与 Docker Compose v2。
- 已克隆本仓库到 `DEPLOY_ROOT`，且 `scripts/*.sh` 可执行。
- SSH 用户可执行 `docker` 与 `docker compose`（将用户加入 `docker` 组或使用 root）。
- 首次部署前在 `projects/ai/project.env` 中写入与镜像仓库一致的 `TAG_*`（或使用 CI 覆盖），**禁止使用 `latest` 作为运行标签**。

## Prometheus（扩展）

在 Nest 应用暴露 `/metrics` 后，可将 `projects/ai/nginx/conf.d/20-default.conf` 中 `location = /metrics` 改为 `proxy_pass` 到后端或 sidecar，并在监控栈中抓取该路径。
