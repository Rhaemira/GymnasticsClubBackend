#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v swift >/dev/null || { echo "Swift 6.0+ is required." >&2; exit 1; }
SWIFT_VERSION="$(swift --version | sed -nE 's/.*Swift version ([0-9]+(\.[0-9]+)*).*/\1/p' | head -n 1)"
SWIFT_MAJOR="${SWIFT_VERSION%%.*}"
if [[ -z "$SWIFT_VERSION" || "$SWIFT_MAJOR" -lt 6 ]]; then
    echo "Swift 6.0 or newer is required; found: ${SWIFT_VERSION:-unknown}." >&2
    exit 1
fi

if [[ ! -f Package.swift ]]; then
    echo "Package.swift was not found. Run this script from a valid repository checkout." >&2
    exit 1
fi

if [[ ! -f .env ]]; then
    cp .env.example .env
    chmod 600 .env
    echo "Created .env with local development defaults. Edit DATABASE_PASSWORD before continuing."
else
    echo "Keeping existing .env."
fi

swift --version
swift package resolve
echo "Dependencies are ready. Start PostgreSQL, create the configured database, then run Scripts/migrate.sh."
