#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo "Missing .env. Run Scripts/setup.sh." >&2; exit 1; }
set -a; source .env; set +a
read -r -p "Administrator email: " ADMIN_EMAIL
read -r -s -p "Initial password (12+ characters): " ADMIN_INITIAL_PASSWORD; printf '\n'
export ADMIN_EMAIL ADMIN_INITIAL_PASSWORD
swift run create-admin
unset ADMIN_INITIAL_PASSWORD
