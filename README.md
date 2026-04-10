# deploy-infra

阿里云 ECS 上运行 **ai-frontend**（静态 Nginx）与 **ai-backend**（NestJS）的 **蓝绿部署** 编排仓库：边缘 Nginx、Compose、脚本与 CI/CD 模板（GitHub Actions）。

## 目录结构

```text
deploy-infra/
├── projects/ai/
│   ├── compose.yml              # frontend_blue/green + backend_blue/green + edge nginx
│   ├── nginx/                   # 边缘路由与 upstream（10-upstreams.conf 由脚本改写）
│   ├── state/                   # 当前流量落在 blue 还是 green
│   └── project.env              # 镜像仓库、TAG_*（禁止 latest）
├── environments/{dev,test,prod}/ai.env
├── scripts/
│   ├── blue-green-deploy.sh     # 发布：起新槽位 → 健康检查 → 切流量 → 删旧容器
│   ├── deploy.sh                # 全量 up（首次/运维）
│   ├── switch.sh                # 仅切流量
│   ├── rollback.sh              # 恢复 upstream 快照
│   ├── health-check.sh          # 边缘 /health 与 /api/health
│   └── login-acr.sh             # 读 .env.local 并 docker login ACR
├── templates/
│   ├── docker/                  # 复制到 ai-frontend / ai-backend 仓库的 Dockerfile 模板
│   └── github/                  # 复制为各应用仓库的 .github/workflows/ci-cd.yml
└── docs/GITHUB_SECRETS.md
```

## 快速开始（ECS）

1. 克隆到服务器，例如 `~/deploy-infra`。
2. 编辑 `projects/ai/project.env`：设置 `REGISTRY`、`NAMESPACE` 与四个 `TAG_*`（首次可填同一有效 tag，**不要用 latest**）。
3. 按需编辑 `environments/prod/ai.env`（`PUBLIC_BASE_URL`、`CORS_ORIGIN`、`EDGE_*_URL`）。
4. 登录镜像仓库并启动全栈：

   **不必每次手敲长命令。** 任选其一：

   - **脚本（本机 / ECS 上运维）**：将 `projects/ai/.env.local.example` 复制为 `projects/ai/.env.local`，填入 `ACR_USERNAME`、`ACR_PASSWORD`（已在 `.gitignore`，勿提交）。然后：

     ```bash
     chmod +x scripts/*.sh
     ./scripts/login-acr.sh
     ./scripts/deploy.sh prod
     ```

   - **CI 推送部署**：`templates/github/*` 里的 workflow 通过 SSH 在服务器上执行 `docker login`，**不要求**你在 ECS 上重复登录，除非镜像凭证过期或你要首次手动物理 `pull`。

   **关于「连上 ECS」**（SSH）：这是登录**服务器**的方式，和 `docker login` 是两件事。CI 会用你配的 `SSH_KEY` 替你连上去执行命令；你自己维护时仍用 `ssh user@ip`，无法用本仓库脚本代替「拿到一台 ECS shell」这一步，除非改用阿里云 Session Manager 等其他入口。

5. 发布新版本（由 CI 调用或手动）：

   ```bash
   ./scripts/blue-green-deploy.sh frontend 20260408-abc1234 prod
   ./scripts/blue-green-deploy.sh backend  20260408-def5678 prod
   ```

## 蓝绿与回滚

- **蓝绿**：`frontend_blue` / `frontend_green` 与 `backend_blue` / `backend_green` 两两互斥升级；`nginx/conf.d/10-upstreams.conf` 指向当前活跃槽位。
- **健康检查**：新槽位容器 `healthcheck` 通过后，脚本再 `nginx -s reload`，并对边缘（默认 `http://127.0.0.1:${PUBLIC_HTTP_PORT}/health` 与 `/api/health`）做 `curl`；失败则恢复 upstream 快照并退出非零。
- **回滚**：`./scripts/rollback.sh prod` 恢复最近一次部署前保存的 upstream 与 `state/*.active`；若旧容器已被删除，需用已知 tag 再次执行 `blue-green-deploy` 拉旧镜像。

## 应用仓库集成

1. **Dockerfile**：将 `templates/docker/frontend.Dockerfile`、`templates/docker/backend.Dockerfile` 拷入对应仓库根目录；前端需增加 `docker/nginx/default.conf`（可参考 `templates/docker/docker-nginx-default.conf`）。
2. **GitHub Actions**：将 `templates/github/ai-frontend-ci-cd.yml`、`templates/github/ai-backend-ci-cd.yml` 复制为各仓库的 `.github/workflows/ci-cd.yml`。
3. 在 GitHub 配置 Secrets，见 [docs/GITHUB_SECRETS.md](docs/GITHUB_SECRETS.md)。

## 版本号规范

镜像 tag 格式：`YYYYMMDD-<7位 commit 短 SHA>`（与 CI 中 `date -u +%Y%m%d` + `GITHUB_SHA` 一致）。**禁止**在生产使用 `latest`。

## 分支与环境映射（CI 模板）

| 分支 | deploy_env（传给 `blue-green-deploy.sh`） |
|------|------------------------------------------|
| `main` | `prod` |
| `develop` | `dev` |
| `test` | `test` |

## 故障排查

- **`ai-stack-nginx-1` 一直 `Restarting`，`health-check.sh` 报 Connection refused**：边缘 Nginx 未监听端口。先 `docker logs ai-stack-nginx-1` 看是否有 `[emerg]`。同步本仓库最新 `compose.yml`（`nginx` 已改为在四个应用 **healthy** 后再启动）与 `10-upstreams.conf`（已去掉 upstream `keepalive`，避免与 `proxy_pass` 组合导致启动失败）。然后在 `projects/ai` 下执行 `docker compose ... up -d --force-recreate nginx` 或整栈重拉。
- **宿主机 80 被占用**：把 `environments/<env>/ai.env` 的 `PUBLIC_HTTP_PORT` 改为 `8080` 等，并保证与 `deploy.sh` 实际映射一致。

## 注意事项

- **双后端同时挂载 `backend_storage`**：蓝绿切换瞬间两实例可能同时访问同一目录；若存在本地文件锁竞争，应改为对象存储或加分布式锁。
- **日志**：Compose 已配置 `json-file` 日志轮转；生产可接 ELK / Loki。
- **监控**：见 `docs/GITHUB_SECRETS.md` 中 Prometheus 扩展说明。
