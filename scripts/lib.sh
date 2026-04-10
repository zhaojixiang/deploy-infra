#!/usr/bin/env bash
# Shared helpers for deploy-infra (sourced by other scripts).
# shellcheck disable=SC2034

_DEPLOY_INFRA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$_DEPLOY_INFRA_ROOT/projects/ai"
STATE_DIR="$PROJECT_DIR/state"
UPSTREAMS="$PROJECT_DIR/nginx/conf.d/10-upstreams.conf"
ROLLBACK_DIR="$STATE_DIR/rollback"

_compose_env=()

load_project_env() {
  local env="${1:-prod}"
  _compose_env=(
    --env-file "$PROJECT_DIR/project.env"
    --env-file "$_DEPLOY_INFRA_ROOT/environments/$env/ai.env"
  )
  if [[ -f "$PROJECT_DIR/.env.local" ]]; then
    _compose_env+=(--env-file "$PROJECT_DIR/.env.local")
  fi
  set -a
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/project.env"
  # shellcheck source=/dev/null
  source "$_DEPLOY_INFRA_ROOT/environments/$env/ai.env"
  if [[ -f "$PROJECT_DIR/.env.local" ]]; then
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env.local"
  fi
  set +a
}

compose() {
  (cd "$PROJECT_DIR" && docker compose "${_compose_env[@]}" "$@")
}

to_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

opposite_slot() {
  case "$1" in
    blue) echo green ;;
    green) echo blue ;;
    *) echo "invalid slot: $1" >&2; return 1 ;;
  esac
}

write_upstreams() {
  local fe="$1"
  local be="$2"
  cat > "$UPSTREAMS" <<EOF
# Rewritten by deploy scripts — do not edit by hand during deploy
upstream frontend_active {
    server frontend_${fe}:80;
}

upstream backend_active {
    server backend_${be}:3000;
}
EOF
}

ensure_rollback_dir() {
  mkdir -p "$ROLLBACK_DIR"
}

save_deploy_snapshot() {
  ensure_rollback_dir
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$STATE_DIR/frontend.active" "$ROLLBACK_DIR/frontend.active.$ts.bak" 2>/dev/null || true
  cp "$STATE_DIR/backend.active" "$ROLLBACK_DIR/backend.active.$ts.bak" 2>/dev/null || true
  cp "$UPSTREAMS" "$ROLLBACK_DIR/upstreams.conf.$ts.bak" 2>/dev/null || true
  # Pointer to latest for rollback.sh
  ln -sf "frontend.active.$ts.bak" "$ROLLBACK_DIR/frontend.active.LATEST"
  ln -sf "backend.active.$ts.bak" "$ROLLBACK_DIR/backend.active.LATEST"
  ln -sf "upstreams.conf.$ts.bak" "$ROLLBACK_DIR/upstreams.conf.LATEST"
}

wait_service_healthy() {
  local svc="$1"
  local deadline=$(( $(date +%s) + 180 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    local cid
    cid="$(compose ps -q "$svc" 2>/dev/null || true)"
    if [[ -n "$cid" ]]; then
      local st
      st="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$cid" 2>/dev/null || echo unknown)"
      if [[ "$st" == "healthy" ]]; then
        return 0
      fi
      if [[ "$st" == "no-healthcheck" ]]; then
        st="$(docker inspect --format='{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
        if [[ "$st" == "running" ]]; then
          return 0
        fi
      fi
    fi
    sleep 3
  done
  echo "Timeout waiting for $svc to become healthy" >&2
  return 1
}

verify_frontend_slot() {
  local target="$1"
  if compose exec -T "frontend_${target}" wget -qO- http://127.0.0.1/health >/dev/null 2>&1; then
    return 0
  fi
  echo "Frontend slot $target failed in-container health probe" >&2
  return 1
}

verify_backend_slot() {
  local target="$1"
  if compose exec -T "backend_${target}" curl -fsS "http://127.0.0.1:3000/health" >/dev/null 2>&1; then
    return 0
  fi
  echo "Backend slot $target failed in-container health probe" >&2
  return 1
}

reload_nginx() {
  compose exec -T nginx nginx -t
  compose exec -T nginx nginx -s reload
}

check_edge_health() {
  local env="${1:-${ENVIRONMENT:-prod}}"
  load_project_env "$env"
  local h="${EDGE_HEALTH_URL:-http://127.0.0.1:${PUBLIC_HTTP_PORT:-80}/health}"
  local a="${EDGE_API_HEALTH_URL:-http://127.0.0.1:${PUBLIC_HTTP_PORT:-80}/api/health}"
  curl -fsS "$h" >/dev/null
  curl -fsS "$a" >/dev/null
}
