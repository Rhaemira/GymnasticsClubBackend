#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo "Missing .env. Run Scripts/setup.sh." >&2; exit 1; }
set -a
source .env
set +a

: "${DATABASE_HOST:?Missing DATABASE_HOST}"
: "${DATABASE_PORT:?Missing DATABASE_PORT}"
: "${DATABASE_NAME:?Missing DATABASE_NAME}"
: "${DATABASE_USERNAME:?Missing DATABASE_USERNAME}"
: "${DATABASE_PASSWORD:?Missing DATABASE_PASSWORD}"
PORT="${PORT:-8080}"

if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -d "$DATABASE_NAME" >/dev/null || {
        echo "PostgreSQL at $DATABASE_HOST:$DATABASE_PORT is not ready for database $DATABASE_NAME." >&2
        echo "Start PostgreSQL and verify DATABASE_* values in .env." >&2
        exit 1
    }
fi

if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Port $PORT is already in use. Stop the process or choose another PORT in .env." >&2
    exit 1
fi

echo "Starting Gymnastics Club API on 0.0.0.0:$PORT."
exec swift run serve --hostname 0.0.0.0 --port "$PORT"
