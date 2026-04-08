# Place as ai-backend/Dockerfile — build context = repository root.

# syntax=docker/dockerfile:1

FROM node:20-bookworm AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@9 --activate

COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm run build

FROM node:20-bookworm-slim AS runner

ARG GIT_SHA=unknown
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
 && rm -rf /var/lib/apt/lists/*

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

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
  CMD curl -fsS http://127.0.0.1:3000/health || exit 1

CMD ["node", "dist/main.js"]
