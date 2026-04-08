#!/usr/bin/env bash
# Hit edge /health and /api/health (see environments/*/ai.env).
# Usage: ./health-check.sh [dev|test|prod]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ENVIRONMENT="${1:-${ENVIRONMENT:-prod}}"
export ENVIRONMENT

check_edge_health "$ENVIRONMENT"
echo "Edge health OK ($ENVIRONMENT)"
