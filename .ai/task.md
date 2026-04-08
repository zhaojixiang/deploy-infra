你是一个资深 DevOps 架构师 + 全栈工程师，请为一个前端项目设计并实现一套“可直接运行”的企业级 CI/CD 自动化部署方案。

# 一、项目背景

- 前后端分离项目
- 前端：ai-frontend
- 后端：ai-backend
- 前后端通过 HTTP 协议通信
- 前端项目使用 React + TypeScript
- 后端项目使用 NestJS + TypeScript
- 前后端项目都使用 阿里云镜像服务
- 前后端项目都使用 GitHub 管理
- 部署环境：阿里云 ECS

# 二、核心目标（必须全部实现）

当代码 push 到 main 分支时，自动完成以下流程：

1. CI 阶段：
   - 安装依赖
   - 构建前端项目
   - 构建 Docker 镜像（必须使用多阶段构建优化体积）
   - 生成唯一版本号（禁止使用 latest）

2. 镜像处理：
   - 自动登录阿里云镜像仓库
   - 推送镜像（带版本 tag）

3. CD 部署阶段（通过 SSH 到服务器）：
   - 更新 docker-compose.yml 中的镜像版本号
   - 拉取最新镜像
   - 启动新版本服务
   - 完成蓝绿切换（不中断服务）

# 三、必须实现的工程能力（重点）

## 1. CI/CD

- 使用 GitHub Actions
- 构建失败必须终止部署
- workflow 结构清晰（build / deploy 分阶段）

## 2. 蓝绿部署（必须实现）

- 定义两个服务：
  - frontend_blue
  - frontend_green
- 使用 nginx 或 docker-compose 控制流量切换
- 发布时新版本先启动，再切换流量

## 3. 自动回滚机制（必须实现）

- 新版本启动后进行健康检查（HTTP 请求）
- 如果健康检查失败：
  - 自动切回旧版本
  - 保持服务可用
- 需要给出具体实现方式（脚本或命令）

## 4. 多环境支持

- 支持 dev / test / prod
- 使用 .env 文件隔离环境变量
- 根据分支自动选择环境：
  - main → prod
  - develop → dev

## 5. 健康检查

- Docker 容器必须配置 healthcheck
- 部署流程中必须检测服务状态（例如 curl /health）

## 6. 版本管理（必须规范）

- 使用 commit hash 或时间戳作为 tag
- 示例：
  ai-frontend:20260407-abc123
- 严禁使用 latest

## 7. Secrets 管理（必须规范）

- 所有敏感信息必须使用 GitHub Secrets：
  - 镜像仓库密码
  - SSH 私钥
- 不允许写死在代码中
- 给出需在 GitHub 中配置的 Secrets 列表

## 8. 日志与扩展能力（轻量实现）

- 容器日志必须可输出（stdout）
- 预留监控扩展能力（例如 prometheus 接入点说明）

# 四、资源信息（必须使用）

阿里云镜像仓库：

- registry: crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com
- namespace: jijiking1
- repository: ai-frontend、ai-backend
- username: JJKing11

# 五、约束（非常重要）

- 所有代码必须是“可运行”的真实配置，不要示例代码
- 不允许省略关键配置
- 不允许使用 latest 标签
- 必须考虑部署失败场景
- 所有变量必须可配置（不要写死）
- 输出要符合生产环境规范（不是 demo）

# 六、参考原配置

可参考以下历史配置信息中的一些关键信息，实现一套新的部署方案，不要照抄配置

- ai-frontend
  docker-compose.yml：

  ```yaml
  services:
  web:
    build:
    context: .
    dockerfile: Dockerfile
    args:
      ENV_BASE: ${ENV_BASE:-/}
      ENV_NAME: ${ENV_NAME:-pro}
      VITE_API_BASE_URL: ${VITE_API_BASE_URL:-}
    ports:
      - "${WEB_PORT:-8080}:80"
    restart: unless-stopped
  ```

  Dockerfile:

  ```
  # --- build ---

        FROM node:20-alpine AS builder

        RUN corepack enable && corepack prepare pnpm@9 --activate

        WORKDIR /app

        COPY package.json pnpm-lock.yaml ./

        RUN pnpm install --frozen-lockfile

        COPY . .

        # 构建期环境变量（与 vite envPrefix: VITE* / ENV* 对齐）

        ARG ENV_BASE=/
        ARG ENV_NAME=pro
        ARG VITE_API_BASE_URL=

        ENV ENV_BASE=$ENV_BASE
        ENV ENV_NAME=$ENV_NAME
        ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

        RUN pnpm run build

        # --- static ---

        FROM nginx:1.27-alpine

        COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
        COPY --from=builder /app/dist /usr/share/nginx/html

        EXPOSE 80

        CMD ["nginx", "-g", "daemon off;"]

  ```

  deploy.yml:

  ```yaml
  name: Deploy Frontend

  on:
  push:
  branches: [main]

  jobs:
  deploy:
  runs-on: ubuntu-latest

        steps:
        - uses: actions/checkout@v4

        - name: Login ACR
            uses: docker/login-action@v3
            with:
            registry: crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com
            username: ${{ secrets.ACR_USERNAME }}
            password: ${{ secrets.ACR_PASSWORD }}

        - name: Build & Push
            uses: docker/build-push-action@v5
            with:
            context: .
            push: true
            tags: |
                crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com/jijiking1/ai-frontend:${{ github.sha }}

        - name: Deploy
            uses: appleboy/ssh-action@v1.0.3
            with:
            host: ${{ secrets.HOST }}
            username: ${{ secrets.USERNAME }}
            key: ${{ secrets.SSH_KEY }}
            script: |
                cd ~/jjtools

                docker login --username=${{ secrets.ACR_USERNAME }} crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com -p ${{ secrets.ACR_PASSWORD }}

                FRONTEND_TAG=${{ github.sha }} docker compose up -d frontend
  ```

- ai-backend
  docker-compose.yml：

  ```yaml
  services:
  app:
    build: .
    image: ai-backend:latest
    ports:
      # 宿主机端口:容器内端口（应用进程内固定监听 3000，与 Dockerfile HEALTHCHECK 一致）
      - "${HOST_PORT:-3000}:3000"
    environment:
      NODE_ENV: ${NODE_ENV:-production}
      PORT: "3000"
      PUBLIC_BASE_URL: ${PUBLIC_BASE_URL:-http://127.0.0.1:3000}
      CORS_ORIGIN: ${CORS_ORIGIN:-*}
      SERVE_STORAGE: ${SERVE_STORAGE:-true}
      MAX_CONCURRENT_VIDEO_JOBS: ${MAX_CONCURRENT_VIDEO_JOBS:-2}
      DOWNLOAD_TIMEOUT_MS: ${DOWNLOAD_TIMEOUT_MS:-600000}
      FFMPEG_TIMEOUT_MS: ${FFMPEG_TIMEOUT_MS:-3600000}
      PYTHON_BIN: ${PYTHON_BIN:-/app/python/venv/bin/python}
    volumes:
      - storage_data:/app/storage
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s
  ```

volumes:
storage_data:

```

Dockerfile:

```

# syntax=docker/dockerfile:1

FROM node:20-bookworm AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@9 --activate

COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm run build

FROM node:20-bookworm-slim AS runner

ARG GIT_SHA
LABEL org.opencontainers.image.title="ai-backend" \
 org.opencontainers.image.revision="${GIT_SHA}"

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
 ca-certificates \
 curl \
 ffmpeg \
 python3 \
 python3-pip \
 python3-venv \
 libglib2.0-0 \
 libgomp1 \
 && rm -rf /var/lib/apt/lists/\*

RUN python3 -m pip install --no-cache-dir --break-system-packages -i https://pypi.tuna.tsinghua.edu.cn/simple yt-dlp \
&& yt-dlp --version

COPY python/requirements.txt ./python/requirements.txt
COPY python/scripts ./python/scripts

RUN python3 -m venv /app/python/venv \
 && /app/python/venv/bin/pip install --no-cache-dir --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple \
 && /app/python/venv/bin/pip install --no-cache-dir -r python/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

RUN corepack enable && corepack prepare pnpm@9 --activate

COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --prod --frozen-lockfile

COPY --from=builder /app/dist ./dist

RUN mkdir -p storage && chown -R node:node /app

USER node

ENV NODE_ENV=production

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
 CMD curl -fsS http://127.0.0.1:3000/health || exit 1

CMD ["node", "dist/main.js"]

```
deploy.yml:
```

name: Deploy Backend (Blue-Green)

on:
push:
branches: [main]

jobs:
deploy:
runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Login ACR
        uses: docker/login-action@v3
        with:
          registry: crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Build & Push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com/jijiking1/ai-backend:${{ github.sha }}

      - name: Deploy (Blue-Green)
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            set -e
            cd ~/jjtools

            echo "==== 登录 ACR ===="
            docker login --username=${{ secrets.ACR_USERNAME }} crpi-3iew34pvm0fklze5.cn-chengdu.personal.cr.aliyuncs.com -p ${{ secrets.ACR_PASSWORD }}

            echo "==== 判断当前运行版本 ===="
            if docker ps | grep backend_blue; then
              CURRENT=blue
              TARGET=green
            else
              CURRENT=green
              TARGET=blue
            fi

            echo "当前版本: $CURRENT -> 新版本: $TARGET"

            echo "==== 启动新版本 ===="
            BACKEND_TAG=${{ github.sha }} docker compose up -d backend_$TARGET

            echo "==== 等待启动 ===="
            sleep 10

            echo "==== 健康检查 ===="
            if curl -f http://localhost:3000/health; then
              echo "✅ 健康检查通过"

              echo "==== 切流量 ===="
              sed -i "s/backend_$CURRENT/backend_$TARGET/g" nginx.conf
              docker exec nginx nginx -s reload

              echo "==== 删除旧版本 ===="
              docker rm -f backend_$CURRENT || true

              echo "🎉 发布完成（零停机）"
            else
              echo "❌ 发布失败，回滚"
              docker rm -f backend_$TARGET || true
              exit 1
            fi

```

```
