#!/usr/bin/env bash
# Log in to Aliyun ACR using credentials from the environment or projects/ai/.env.local.
# The password is not echoed; .env.local is gitignored — do not commit it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$ROOT/projects/ai"
LOCAL_ENV="$PROJECT/.env.local"

set -a
# shellcheck source=/dev/null
source "$PROJECT/project.env"
set +a

if [[ -f "$LOCAL_ENV" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$LOCAL_ENV"
  set +a
fi

if [[ -z "${ACR_USERNAME:-}" || -z "${ACR_PASSWORD:-}" ]]; then
  echo "Missing ACR_USERNAME or ACR_PASSWORD." >&2
  echo "Export them in the shell, or create $LOCAL_ENV with:" >&2
  echo "  ACR_USERNAME=..." >&2
  echo "  ACR_PASSWORD=..." >&2
  exit 1
fi

echo "$ACR_PASSWORD" | docker login "$REGISTRY" -u "$ACR_USERNAME" --password-stdin
echo "Login succeeded: $REGISTRY"
