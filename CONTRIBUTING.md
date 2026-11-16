# Contributing

Thanks for contributing to the Gymnastics Club API.

## Local environment

Use Swift 6 or newer and a dedicated PostgreSQL development/test database. Follow the README's Docker Compose or native macOS quick start. Never run tests or destructive maintenance against production data.

## Branches and pull requests

- Work from the active engineering branch for the current overhaul; do not push directly to `main`.
- Keep changes focused and describe the operational/API impact.
- Update `API_CONTRACT.md` and coordinate the iOS client when request/response behavior changes.
- Explain migration safety, data compatibility, and rollout requirements.
- Include exact validation commands and results. Queued CI is not a pass.

## Code and data expectations

- Keep handlers, DTOs, validation, models, and migrations separated by responsibility.
- Validate all client-controlled input on the server.
- Enforce authorization on the server; never rely on the iOS client as a security boundary.
- Prefer additive migrations. Never rewrite or re-register historical migrations that may already have run.
- Preserve user data; migrations must fail safely rather than silently discard or rewrite ambiguous records.
- Avoid logging credentials, bearer tokens, password hashes, SQL bind values, or personal data.
- Add integration tests for route behavior, validation, authorization, concurrency, and database invariants.

## Validation

Run `swift package resolve`, `swift build`, and `swift test` against a disposable PostgreSQL database. For changes to startup, migrations, or deployment, also validate the native and Docker workflows where applicable.
