# Place as ai-frontend/Dockerfile — build context = repository root.
# Copy nginx-default.conf to docker/nginx/default.conf in the app repo, or adjust COPY paths.

# syntax=docker/dockerfile:1

FROM node:20-alpine AS builder

RUN corepack enable && corepack prepare pnpm@9 --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml ./

RUN pnpm install --frozen-lockfile

COPY . .

ARG ENV_BASE=/
ARG ENV_NAME=pro
ARG VITE_API_BASE_URL=

ENV ENV_BASE=$ENV_BASE
ENV ENV_NAME=$ENV_NAME
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

RUN pnpm run build

FROM nginx:1.27-alpine

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
  CMD wget -qO- http://127.0.0.1/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
