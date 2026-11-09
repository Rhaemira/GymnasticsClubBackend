#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo "Missing .env. Run Scripts/setup.sh." >&2; exit 1; }
set -a; source .env; set +a
: "${DATABASE_HOST:?Missing DATABASE_HOST}"; : "${DATABASE_PORT:?Missing DATABASE_PORT}"; : "${DATABASE_NAME:?Missing DATABASE_NAME}"; : "${DATABASE_USERNAME:?Missing DATABASE_USERNAME}"; : "${DATABASE_PASSWORD:?Missing DATABASE_PASSWORD}"
if command -v pg_isready >/dev/null 2>&1; then pg_isready -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" >/dev/null || { echo "PostgreSQL is not ready." >&2; exit 1; }; fi
swift run serve --hostname 0.0.0.0 --port "${PORT:-8080}"
