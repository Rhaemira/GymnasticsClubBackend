# Security policy

## Supported development line

Security fixes should target the active engineering branch and be proposed through a pull request. Do not publish exploit details in public issues.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature for this repository if it is enabled. If unavailable, contact the repository maintainer privately through GitHub before disclosing details publicly.

Include the affected commit/version, impact, reproduction steps, and a safe proof-of-concept where useful. Never include production data, passwords, bearer tokens, private keys, or unredacted logs.

## Security design notes

- Passwords are hashed with bcrypt; raw passwords are not persisted.
- Bearer tokens are opaque and only SHA-256 digests are stored.
- Administrative routes require authentication.
- Login throttling is currently process-local. Multi-instance deployments require shared edge rate limiting and trusted-proxy configuration.
- Production deployments should use HTTPS, secret management, restricted database access, and TLS to external PostgreSQL.
