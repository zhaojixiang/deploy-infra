#!/usr/bin/env bash
# Restore nginx upstreams from the last snapshot taken by blue-green-deploy.sh.
# Does not recreate removed containers — run deploy with a known tag if needed.
# Usage: ./rollback.sh [environment]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ENVIRONMENT="${1:-${ENVIRONMENT:-prod}}"
export ENVIRONMENT

load_project_env "$ENVIRONMENT"

LATEST="$ROLLBACK_DIR/upstreams.conf.LATEST"
if [[ ! -e "$LATEST" ]]; then
  echo "No snapshot found under $ROLLBACK_DIR" >&2
  exit 1
fi

cp "$LATEST" "$UPSTREAMS"

if [[ -L "$ROLLBACK_DIR/frontend.active.LATEST" ]] || [[ -f "$ROLLBACK_DIR/frontend.active.LATEST" ]]; then
  cp "$ROLLBACK_DIR/frontend.active.LATEST" "$STATE_DIR/frontend.active"
fi
if [[ -L "$ROLLBACK_DIR/backend.active.LATEST" ]] || [[ -f "$ROLLBACK_DIR/backend.active.LATEST" ]]; then
  cp "$ROLLBACK_DIR/backend.active.LATEST" "$STATE_DIR/backend.active"
fi

reload_nginx
echo "Restored upstreams and active-slot files from latest snapshot."
