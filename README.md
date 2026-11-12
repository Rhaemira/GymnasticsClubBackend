# Gymnastics Club Backend

Swift 6 / Vapor 4 API for the Gymnastics Club iOS application. PostgreSQL is the source of truth; all management routes require an administrator bearer token.

## Requirements

- Swift 6.0 or newer (the Docker image uses Swift 6.1)
- PostgreSQL 14+ for native development, or Docker Desktop with Compose v2
- macOS 13+ for native development

## Native macOS setup

From the repository root:

```bash
cp .env.example .env
# Edit .env and set a unique local DATABASE_PASSWORD.
Scripts/setup.sh
```

Create the local database and user using your PostgreSQL installation (the example names below match .env):

```bash
createuser -P gymnastics_dev
createdb -O gymnastics_dev gymnastics_club
```

Then:

```bash
Scripts/migrate.sh
Scripts/start.sh
```

The startup script verifies PostgreSQL readiness and checks that the configured API port is available before launching Vapor. It listens on `0.0.0.0:8080` by default so a physical iPhone on the same trusted development network can reach the Mac. Override `PORT` in `.env` to use another port. Verify database readiness:

```bash
curl -i http://127.0.0.1:8080/health
```

Expected response: HTTP 200 with `{"status":"ok","database":"ready"}`. If PostgreSQL is unreachable or the schema is not migrated, health returns HTTP 503.

### Initial administrator

With the server stopped, or in a second terminal, run:

```bash
Scripts/create-admin.sh
```

The script prompts for the administrator email and password without echoing the password. Administrator passwords must contain at least 12 characters and no more than 72 UTF-8 bytes (the bcrypt input limit). There is no public administrator-registration route.

### Seed data

```bash
set -a; source .env; set +a
swift run GymnasticsClubBackend seed
```

The seed command is idempotent: it reuses matching sample records and does not duplicate enrollments. Use it only in development or a disposable test environment.

### Troubleshooting native startup

When a project has been moved between directories or cloned under a different macOS account, Swift can retain stale build/module-cache paths. Rebuild the Swift package artifacts without touching PostgreSQL data:

```bash
swift package clean
swift package resolve
swift build
Scripts/migrate.sh
Scripts/start.sh
```

If startup reports that the port is occupied, set a free `PORT` in `.env` and use the matching API URL in the iOS Debug build settings. If `/health` returns 503, verify PostgreSQL is accepting connections and that the database and role named in `.env` exist.

## Docker Compose

Copy .env.example to .env and set DATABASE_PASSWORD. Start the complete stack:

```bash
docker compose up --build -d
docker compose ps
curl -i http://127.0.0.1:8080/health
docker compose logs -f app
```

Compose waits for PostgreSQL health, runs the one-shot migration service, and only then starts the API. PostgreSQL data is stored in the named `db_data` volume. Ordinary shutdown preserves data:

```bash
docker compose down
```

Do not use `docker compose down -v` on a database containing data. The database port is not published by default. The API is bound to localhost by default; put it behind a TLS-terminating reverse proxy for remote access.

## Configuration

All database settings are required by the application at startup:

| Variable | Purpose |
|---|---|
| DATABASE_HOST | PostgreSQL hostname |
| DATABASE_PORT | PostgreSQL port |
| DATABASE_NAME | Database name |
| DATABASE_USERNAME | Database role |
| DATABASE_PASSWORD | Database password |
| DATABASE_TLS | `disable`, `prefer`, or `require` |
| AUTH_TOKEN_TTL_SECONDS | Token lifetime, 900–86400 seconds |
| PORT | Native startup script port |

Server logging is intentionally capped at `info`; SQL bind parameters and other debug diagnostics are not emitted. Never commit .env files. Production must use a secret manager or deployment environment, a unique database role/password, and `DATABASE_TLS=require`. The Compose stack uses an unpublished PostgreSQL service on its isolated Docker network; its explicit `DATABASE_TLS_ALLOW_PRIVATE_COMPOSE_LINK` exception is scoped to the service hostname `db`. Do not enable that exception for an externally reachable database.

## Authentication and API

- `POST /auth/login` — public; JSON `{"email":"...","password":"..."}`
- `GET /auth/me` — bearer token required
- `POST /auth/logout` — bearer token required; revokes the presented token
- `GET /health` — public database readiness probe
- `GET /` — public service identity

All athlete, coach, class, enrollment, attendance, dashboard, reports and analytics routes require `Authorization: Bearer <token>`.

Login returns a random opaque token once. The database stores only its SHA-256 digest; passwords are stored using bcrypt. Login failures are rate-limited per remote address and normalized email in an application-instance-scoped in-memory limiter. The tracker is bounded and pruned; a successful login clears only that account's failure history, not the source address's history. This is a single-instance defense, not a distributed security boundary: deploy multiple instances behind a shared edge rate limiter and configure trusted-proxy address handling before scaling horizontally. Unknown accounts receive a bcrypt-cost operation to reduce account-enumeration timing differences. Expired and revoked access-token digests are opportunistically cleaned up during successful login.

Example:

```bash
curl -sS -X POST http://127.0.0.1:8080/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@example.com","password":"your-password"}'
```

Use the returned token in subsequent API calls. Never put tokens in URLs or logs.

## Database migrations

Fluent tracks migrations in its migration table. The historical `FixCascadeDeletes` migration drops and recreates populated tables and is deliberately not registered. Do not execute it. Existing migration files are retained unchanged. New schema changes use additive migrations.

## Tests

```bash
swift test
```

GitHub Actions runs the same Swift build/test and native migration, administrator creation, server startup, health and authenticated CRUD flow on a macOS runner, in addition to the Linux PostgreSQL/Docker pipeline.

The integration suite requires a real PostgreSQL test database. Set the same DATABASE_* variables to a dedicated disposable test database before running tests. Never point tests at production data. Coverage includes protected routes, token expiry and revocation, login throttling, athlete/coach/class/attendance CRUD, validation, class capacity and concurrent enrollment, attendance uniqueness under concurrent inserts, fractional and whole-second date coding, transactional dependent-record deletion, reports and analytics.

The attendance uniqueness migration is additive. It never removes historical records. If it detects duplicate historical attendance rows, it aborts with a clear error rather than silently discarding data. Review those rows and resolve them through an explicit, audited data-maintenance operation before retrying.

## Production deployment

Terminate HTTPS at a trusted reverse proxy/load balancer. Configure it to strip untrusted incoming forwarding headers and add its own forwarding metadata. Restrict network access to PostgreSQL, inject secrets from a secret manager, run migrations as a deployment step, and monitor `/health` plus application logs. Do not expose the database publicly.
