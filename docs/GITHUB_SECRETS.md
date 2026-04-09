# GitHub Secrets 清单

## 哪些仓库需要配置

| 仓库             | 是否需要下表中的 Secrets | 说明                                                                                                                                         |
| ---------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **ai-frontend**  | **需要**                 | 使用 `templates/github/ai-frontend-ci-cd.yml` 时：构建镜像、推送 ACR、SSH 部署依赖这些凭证。                                                 |
| **ai-backend**   | **需要**                 | 使用 `templates/github/ai-backend-ci-cd.yml` 时：同上。                                                                                      |
| **deploy-infra** | **一般不需要**           | 本仓库当前仅有 `docker compose config` 等校验 workflow，不登录 ACR、不 SSH。若日后在本仓库增加「推镜像 / 远程部署」类 workflow，再按需添加。 |

**避免重复配置**：可在 **GitHub Organization** 中配置**组织级 Secrets**，并对 `ai-frontend`、`ai-backend` 授权使用，这样两个应用仓库无需各自维护一套同名变量。

不要在任何仓库中提交明文密码或私钥。

## Secrets 列表

将以下 Secrets 配置在 **ai-frontend** 与 **ai-backend**（或组织级，见上文）中：

| Secret         | 说明                                                            |
| -------------- | --------------------------------------------------------------- |
| `ACR_USERNAME` | 阿里云容器镜像服务登录用户名                                    |
| `ACR_PASSWORD` | 阿里云容器镜像服务登录密码（或具有推送权限的临时令牌）          |
| `SSH_HOST`     | ECS 公网 IP 或主机名（SSH 目标）                                |
| `SSH_USERNAME` | SSH 登录用户（通常为 `root` 或具有 docker 权限的用户）          |
| `SSH_KEY`      | SSH 私钥全文（OpenSSH 格式，`-----BEGIN ... PRIVATE KEY-----`） |
| `DEPLOY_ROOT`  | （可选）服务器上本仓库克隆路径，默认 `~/deploy-infra`           |

可选：若按环境拆分主机，可在 workflow 中自行改为 `SSH_HOST_PROD` / `SSH_HOST_DEV` 等表达式（需同步修改 `templates/github/*.yml`）。

## ECS 上手动拉镜像时

GitHub Actions 在 SSH 脚本里已包含 `docker login`，日常发布通常**不用**你在服务器上手敲。若你本地/首次在 ECS 上执行 `./scripts/deploy.sh`，可用 **`./scripts/login-acr.sh`**：在 **`projects/ai/.env.local`**（已 gitignore，参考 `projects/ai/.env.local.example`）写入与 ACR 一致的 `ACR_USERNAME`、`ACR_PASSWORD` 即可，不必把长 `docker login` 命令敲进终端历史。

## 服务器侧要求

- 已安装 Docker Engine 与 Docker Compose v2。
- 已克隆本仓库到 `DEPLOY_ROOT`，且 `scripts/*.sh` 可执行。
- SSH 用户可执行 `docker` 与 `docker compose`（将用户加入 `docker` 组或使用 root）。
- 首次部署前在 `projects/ai/project.env` 中写入与镜像仓库一致的 `TAG_*`（或使用 CI 覆盖），**禁止使用 `latest` 作为运行标签**。

## Prometheus（扩展）

在 Nest 应用暴露 `/metrics` 后，可将 `projects/ai/nginx/conf.d/20-default.conf` 中 `location = /metrics` 改为 `proxy_pass` 到后端或 sidecar，并在监控栈中抓取该路径。
