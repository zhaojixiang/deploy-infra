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
│   └── health-check.sh          # 边缘 /health 与 /api/health
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

   ```bash
   chmod +x scripts/*.sh
   echo "$ACR_PASSWORD" | docker login crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com -u "$ACR_USERNAME" --password-stdin
   ./scripts/deploy.sh prod
   ```

5. 发布新版本（由 CI 调用或手动）：

   ```bash
   ./scripts/blue-green-deploy.sh frontend 20260408-abc1234 prod
   ./scripts/blue-green-deploy.sh backend  20260408-def5678 prod
   ```

## 蓝绿与回滚

- **蓝绿**：`frontend_blue` / `frontend_green` 与 `backend_blue` / `backend_green` 两两互斥升级；`nginx/conf.d/10-upstreams.conf` 指向当前活跃槽位。
- **健康检查**：新槽位容器 `healthcheck` 通过后，脚本再 `nginx -s reload`，并对边缘 `EDGE_HEALTH_URL`、`EDGE_API_HEALTH_URL` 做 `curl`；失败则恢复 upstream 快照并退出非零。
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

## 注意事项

- **双后端同时挂载 `backend_storage`**：蓝绿切换瞬间两实例可能同时访问同一目录；若存在本地文件锁竞争，应改为对象存储或加分布式锁。
- **日志**：Compose 已配置 `json-file` 日志轮转；生产可接 ELK / Loki。
- **监控**：见 `docs/GITHUB_SECRETS.md` 中 Prometheus 扩展说明。
