#!/usr/bin/env bash
# Manually point edge nginx at a slot without pulling a new image.
# Usage: ./switch.sh <frontend|backend> <blue|green> [environment]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ROLE="${1:-}"
SLOT="${2:-}"
ENVIRONMENT="${3:-${ENVIRONMENT:-prod}}"

usage() {
  echo "Usage: $0 <frontend|backend> <blue|green> [environment]" >&2
  exit 1
}

[[ -z "$ROLE" || -z "$SLOT" ]] && usage
case "$SLOT" in
  blue|green) ;;
  *) usage ;;
esac

export ENVIRONMENT
load_project_env "$ENVIRONMENT"

FE="$(tr -d '[:space:]' < "$STATE_DIR/frontend.active")"
BE="$(tr -d '[:space:]' < "$STATE_DIR/backend.active")"

case "$ROLE" in
  frontend)
    FE="$SLOT"
    echo "$FE" > "$STATE_DIR/frontend.active"
    ;;
  backend)
    BE="$SLOT"
    echo "$BE" > "$STATE_DIR/backend.active"
    ;;
  *)
    usage
    ;;
esac

write_upstreams "$FE" "$BE"
reload_nginx
echo "Switched: frontend=$FE backend=$BE"
