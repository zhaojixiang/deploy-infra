#!/usr/bin/env bash
# Bring up the full ai stack (all services). Does not perform blue/green promotion.
# Usage: ./deploy.sh [dev|test|prod]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ENVIRONMENT="${1:-${ENVIRONMENT:-prod}}"
export ENVIRONMENT

load_project_env "$ENVIRONMENT"
compose up -d --remove-orphans
