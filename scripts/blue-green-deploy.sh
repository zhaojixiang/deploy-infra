#!/usr/bin/env bash
# Blue/green deploy for ai stack.
# Usage:
#   ./blue-green-deploy.sh frontend <TAG> [environment]
#   ./blue-green-deploy.sh backend  <TAG> [environment]
#   ./blue-green-deploy.sh all      <FRONTEND_TAG> <BACKEND_TAG> [environment]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  echo "Usage: $0 frontend <TAG> [environment]" >&2
  echo "       $0 backend  <TAG> [environment]" >&2
  echo "       $0 all      <FRONTEND_TAG> <BACKEND_TAG> [environment]" >&2
  exit 1
}

COMPONENT="${1:-}"
[[ -z "$COMPONENT" ]] && usage
shift

deploy_frontend() {
  local TAG="$1"
  local ACTIVE TARGET BACTIVE
  ACTIVE="$(tr -d '[:space:]' < "$STATE_DIR/frontend.active")"
  TARGET="$(opposite_slot "$ACTIVE")"
  BACTIVE="$(tr -d '[:space:]' < "$STATE_DIR/backend.active")"

  save_deploy_snapshot

  echo "==> Deploy frontend: active=$ACTIVE target=$TARGET new_tag=$TAG env=$ENVIRONMENT"

  load_project_env "$ENVIRONMENT"
  local VAR="TAG_FRONTEND_$(to_upper "$TARGET")"
  export "$VAR=$TAG"

  compose up -d "frontend_${TARGET}"

  if ! wait_service_healthy "frontend_${TARGET}"; then
    echo "❌ New frontend slot did not become healthy; stopping $TARGET" >&2
    compose stop "frontend_${TARGET}" || true
    exit 1
  fi
  if ! verify_frontend_slot "$TARGET"; then
    compose stop "frontend_${TARGET}" || true
    exit 1
  fi

  write_upstreams "$TARGET" "$BACTIVE"
  if ! reload_nginx; then
    echo "❌ nginx reload failed; restoring upstreams" >&2
    if [[ -L "$ROLLBACK_DIR/upstreams.conf.LATEST" ]] || [[ -f "$ROLLBACK_DIR/upstreams.conf.LATEST" ]]; then
      cp "$ROLLBACK_DIR/upstreams.conf.LATEST" "$UPSTREAMS"
    fi
    compose exec -T nginx nginx -s reload || true
    compose stop "frontend_${TARGET}" || true
    exit 1
  fi

  echo "$TARGET" > "$STATE_DIR/frontend.active"
  echo "$TAG" > "$STATE_DIR/frontend.tag.${TARGET}"

  if ! check_edge_health "$ENVIRONMENT"; then
    echo "❌ Edge health failed after switch; rolling back upstream" >&2
    if [[ -L "$ROLLBACK_DIR/upstreams.conf.LATEST" ]] || [[ -f "$ROLLBACK_DIR/upstreams.conf.LATEST" ]]; then
      cp "$ROLLBACK_DIR/upstreams.conf.LATEST" "$UPSTREAMS"
    fi
    reload_nginx || true
    echo "$ACTIVE" > "$STATE_DIR/frontend.active"
    compose stop "frontend_${TARGET}" || true
    exit 1
  fi

  echo "==> Removing old frontend slot: $ACTIVE"
  compose stop "frontend_${ACTIVE}" || true
  compose rm -f "frontend_${ACTIVE}" || true

  echo "✅ Frontend deploy complete (traffic on $TARGET)"
}

deploy_backend() {
  local TAG="$1"
  local ACTIVE TARGET FACTIVE
  ACTIVE="$(tr -d '[:space:]' < "$STATE_DIR/backend.active")"
  TARGET="$(opposite_slot "$ACTIVE")"
  FACTIVE="$(tr -d '[:space:]' < "$STATE_DIR/frontend.active")"

  save_deploy_snapshot

  echo "==> Deploy backend: active=$ACTIVE target=$TARGET new_tag=$TAG env=$ENVIRONMENT"

  load_project_env "$ENVIRONMENT"
  local VAR="TAG_BACKEND_$(to_upper "$TARGET")"
  export "$VAR=$TAG"

  compose up -d "backend_${TARGET}"

  if ! wait_service_healthy "backend_${TARGET}"; then
    echo "❌ New backend slot did not become healthy; stopping $TARGET" >&2
    compose stop "backend_${TARGET}" || true
    exit 1
  fi
  if ! verify_backend_slot "$TARGET"; then
    compose stop "backend_${TARGET}" || true
    exit 1
  fi

  write_upstreams "$FACTIVE" "$TARGET"
  if ! reload_nginx; then
    echo "❌ nginx reload failed; restoring upstreams" >&2
    if [[ -L "$ROLLBACK_DIR/upstreams.conf.LATEST" ]] || [[ -f "$ROLLBACK_DIR/upstreams.conf.LATEST" ]]; then
      cp "$ROLLBACK_DIR/upstreams.conf.LATEST" "$UPSTREAMS"
    fi
    compose exec -T nginx nginx -s reload || true
    compose stop "backend_${TARGET}" || true
    exit 1
  fi

  echo "$TARGET" > "$STATE_DIR/backend.active"
  echo "$TAG" > "$STATE_DIR/backend.tag.${TARGET}"

  if ! check_edge_health "$ENVIRONMENT"; then
    echo "❌ Edge health failed after switch; rolling back upstream" >&2
    if [[ -L "$ROLLBACK_DIR/upstreams.conf.LATEST" ]] || [[ -f "$ROLLBACK_DIR/upstreams.conf.LATEST" ]]; then
      cp "$ROLLBACK_DIR/upstreams.conf.LATEST" "$UPSTREAMS"
    fi
    reload_nginx || true
    echo "$ACTIVE" > "$STATE_DIR/backend.active"
    compose stop "backend_${TARGET}" || true
    exit 1
  fi

  echo "==> Removing old backend slot: $ACTIVE"
  compose stop "backend_${ACTIVE}" || true
  compose rm -f "backend_${ACTIVE}" || true

  echo "✅ Backend deploy complete (traffic on $TARGET)"
}

case "$COMPONENT" in
  frontend|backend)
    TAG="${1:-}"
    ENVIRONMENT="${2:-${ENVIRONMENT:-prod}}"
    [[ -z "$TAG" ]] && usage
    export ENVIRONMENT
    if [[ "$COMPONENT" == "frontend" ]]; then
      deploy_frontend "$TAG"
    else
      deploy_backend "$TAG"
    fi
    ;;
  all)
    FE_TAG="${1:-}"
    BE_TAG="${2:-}"
    ENVIRONMENT="${3:-${ENVIRONMENT:-prod}}"
    [[ -z "$FE_TAG" || -z "$BE_TAG" ]] && usage
    export ENVIRONMENT
    deploy_frontend "$FE_TAG"
    deploy_backend "$BE_TAG"
    ;;
  *)
    usage
    ;;
esac
