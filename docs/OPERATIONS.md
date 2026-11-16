# Operations: backups, restores and production readiness

This document describes a conservative PostgreSQL backup/restore procedure. A healthy /health response is not a backup, and a persistent Docker volume is not a backup.

## Backup

Use a dedicated backup identity with minimum required PostgreSQL privileges. Store backups outside the application host, encrypt them at rest and in transit, restrict access, and apply a documented retention policy.

For native PostgreSQL, load the environment without printing it:

```bash
set -a
source .env
set +a
umask 077
BACKUP_FILE="gymnastics-club-$(date -u +%Y%m%dT%H%M%SZ).dump"
pg_dump --host "$DATABASE_HOST" --port "$DATABASE_PORT" \
  --username "$DATABASE_USERNAME" --dbname "$DATABASE_NAME" \
  --format=custom --no-owner --file "$BACKUP_FILE"
```

For the Compose database service:

```bash
set -a
source .env
set +a
umask 077
BACKUP_FILE="gymnastics-club-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker compose exec -T db pg_dump -U "$DATABASE_USERNAME" \
  -d "$DATABASE_NAME" --format=custom --no-owner > "$BACKUP_FILE"
```

Verify that the archive can be read before moving it to protected backup storage:

```bash
pg_restore --list "$BACKUP_FILE" >/dev/null
```

A successful dump command and archive listing do not prove recoverability. Perform restore drills regularly.

## Restore drill

Restore into a new, isolated database first. Never test a restore over the only production database.

```bash
createdb gymnastics_restore_drill
pg_restore --no-owner --dbname gymnastics_restore_drill "$BACKUP_FILE"
```

Run application integration checks against that restored database using a temporary .env or isolated deployment configuration. Verify representative athletes, coaches, classes, enrollments and attendance records, and confirm database constraints and migration history are present. Record restore duration and the data-loss window.

After validation, remove only the isolated drill database:

```bash
dropdb gymnastics_restore_drill
```

For an actual incident, restore to a new database or server, validate it, then switch the application connection deliberately. Keep the original database untouched until recovery is accepted.

## Deployment checklist

- Terminate HTTPS at a correctly configured reverse proxy.
- If the proxy is the direct TCP peer, set its exact IP in TRUSTED_PROXY_IPS and configure it to overwrite X-Real-IP. Do not trust client-supplied forwarding headers.
- Use DATABASE_TLS=require for external PostgreSQL connections.
- Use a dedicated database role; do not run the API as a PostgreSQL superuser.
- Keep native BIND_ADDRESS=127.0.0.1 unless remote access is deliberately required.
- Configure shared edge rate limiting before running multiple API instances; the in-process limiter is not distributed.
- Monitor health, authentication failures, database capacity, backup completion and restore-drill results.
- Keep secrets out of source control, CI logs, shell history and support bundles.
- Run migrations as a controlled deployment step and review migration output before serving traffic.
