#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
command -v swift >/dev/null || { echo "Swift 6.0+ is required." >&2; exit 1; }
if [[ ! -f .env ]]; then cp .env.example .env; chmod 600 .env; echo "Created .env. Edit DATABASE_PASSWORD."; else echo "Keeping existing .env."; fi
swift --version
swift package resolve
echo "Start PostgreSQL and create the configured database, then run Scripts/migrate.sh."
