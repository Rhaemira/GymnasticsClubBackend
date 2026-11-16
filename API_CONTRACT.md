# Gymnastics Club API contract

This document is the shared contract for the SwiftUI client and the Swift/Vapor service. The iOS client and backend must be changed together when this contract changes.

## Conventions

- Base URL: `https://<api-host>` in production; local development uses the URL configured in Xcode.
- Content type: `application/json` for JSON request and response bodies.
- Authentication: every management route requires `Authorization: Bearer <opaque-token>`, except the public routes explicitly listed below.
- UUIDs: canonical UUID strings in JSON and URL path segments.
- Dates: ISO-8601 UTC timestamps. Responses include fractional seconds; requests with or without fractional seconds are accepted.
- JSON property names use the spellings shown below. Swift property names remain camelCase unless an explicit CodingKey is documented.
- Login tokens are opaque, expire, and are revocable. The server stores only a SHA-256 digest of each token.

## Public endpoints

| Method | Path | Request | Success response | Other relevant statuses |
|---|---|---|---|---|
| GET | `/` | — | Service identity string | — |
| GET | `/health` | — | `{ "status": "ok", "database": "ready" }` | 503 when DB is unavailable |
| POST | `/auth/login` | `{ "email": string, "password": string }` | `LoginResponse` | 400 invalid input; 401 invalid credentials; 429 throttled |

Login input rules:
- Email is trimmed and normalized to lowercase; malformed addresses are rejected with 400.
- Password input must be 1–72 UTF-8 bytes to match bcrypt's input limit. Initial administrator creation additionally requires at least 12 characters.
- Failed logins are limited to five per remote address and normalized email in a rolling 60-second window per running application instance. Multi-instance deployments require a shared edge limiter.
- Unknown accounts receive a bcrypt-cost operation to reduce email-enumeration timing differences.

Login response:

```json
{
  "token": "opaque-token",
  "expiresAt": "2026-11-10T12:34:56.123Z",
  "user": { "id": "UUID", "email": "admin@example.test" }
}
```

## Authenticated endpoints

| Method | Path | Request | Success response | Other relevant statuses |
|---|---|---|---|---|
| GET | `/auth/me` | — | `{ id, email }` | 401 missing, expired or revoked token |
| POST | `/auth/logout` | — | 204 No Content | 401 missing/invalid token |
| GET | `/athletes` | — | `Athlete[]` | 401 |
| POST | `/athletes` | `WriteAthleteDTO` | `Athlete` | 400 validation |
| PUT | `/athletes/:athleteID` | `WriteAthleteDTO` | `Athlete` | 400 invalid UUID/validation; 404 missing athlete |
| DELETE | `/athletes/:athleteID` | — | 200 OK | 400 invalid UUID; 404 missing athlete |
| GET | `/coaches` | — | `Coach[]` | 401 |
| POST | `/coaches` | `WriteCoachDTO` | `Coach` | 400 validation; 409 duplicate name |
| PUT | `/coaches/:coachID` | `WriteCoachDTO` | `Coach` | 400 invalid UUID/validation; 404 missing coach; 409 duplicate name |
| DELETE | `/coaches/:coachID` | — | 200 OK | 400 invalid UUID; 404 missing coach |
| GET | `/classes` | — | `ClassResponse[]` | 401 |
| POST | `/classes` | `CreateClassDTO` | `Class` | 400 validation; 404 missing coach |
| PUT | `/classes/:classID` | `CreateClassDTO` | `ClassResponse` | 400 invalid UUID/validation; 404 missing class/coach; 409 capacity conflict |
| DELETE | `/classes/:classID` | — | 200 OK | 400 invalid UUID; 404 missing class |
| GET | `/enrollments` | — | `EnrollmentResponse[]` | 401 |
| POST | `/enrollments` | `CreateEnrollmentDTO` | `EnrollmentResponse` | 404 missing athlete/class; 409 duplicate/full class |
| DELETE | `/enrollments/:enrollmentID` | — | 200 OK | 400 invalid UUID; 404 missing enrollment |
| GET | `/attendance` | — | `AttendanceResponse[]` | 401 |
| POST | `/attendance` | `CreateAttendanceDTO` | `AttendanceResponse` | 400 invalid/future date; 404 missing athlete/class; 409 duplicate |
| PUT | `/attendance/:attendanceID` | `CreateAttendanceDTO` | `AttendanceResponse` | 400 invalid UUID/date; 404 missing record/athlete/class; 409 duplicate |
| DELETE | `/attendance/:attendanceID` | — | 200 OK | 400 invalid UUID; 404 missing attendance |
| GET | `/reports` | — | `ReportsResponse` | 401 |
| GET | `/analytics` | — | `AnalyticsResponse` | 401 |
| GET | `/dashboard` | — | Legacy `DashboardResponse[]` | 401 |

## Request DTOs

### Athlete

```json
{ "fullName": "Taylor Gymnast", "age": 14, "level": "Beginner" }
```

- Name: 2–100 non-whitespace characters.
- Age: 1–120.
- Level: Beginner, Intermediate, Advanced, or Elite (case-insensitive).

### Coach

```json
{ "fullName": "Coach Name", "specialty": "Artistic Gymnastics" }
```

- Name and specialty: 2–100 non-whitespace characters.

### Class

```json
{ "name": "Floor", "capacity": 12, "coach_id": "UUID" }
```

- Class name: 2–100 non-whitespace characters.
- Capacity: 1–500; PostgreSQL enforces this range and prevents lowering capacity below existing enrollments. The additive migration aborts if historical data violates the invariant; it never deletes or rewrites enrollments.
- `coach_id` is deliberate and must not be changed to `coachID`.

### Enrollment

```json
{ "athlete_id": "UUID", "class_id": "UUID" }
```

- `athlete_id` and `class_id` are required snake_case keys.
- Duplicate athlete/class pairs are rejected.
- Class capacity is enforced in PostgreSQL under concurrency.

### Attendance

```json
{
  "athleteID": "UUID",
  "classID": "UUID",
  "attendedOn": "2026-11-10T12:34:56.123Z"
}
```

- Date must not be more than five minutes in the future.
- A unique database index prevents duplicate athlete/class/timestamp records, including concurrent inserts.

## Response models

### ReportsResponse

```json
{
  "totalAthletes": 12,
  "totalCoaches": 3,
  "totalClasses": 5,
  "totalEnrollments": 18,
  "totalAttendanceRecords": 72
}
```

### AnalyticsResponse

Contains:
- `overview`: athlete, coach, class, enrollment and attendance counts.
- `athleteLevels`: level/count pairs.
- `coachWorkload`: coach/class-count pairs.
- `classUtilization`: class name, enrolled count and capacity.

### Common error behavior

The service uses Vapor's structured error response with a human-readable `reason`. Clients must not treat all 4xx responses as authentication failures. In particular:
- 401: authentication is missing, expired or revoked.
- 403: the authenticated principal lacks permission.
- 404: referenced resource does not exist.
- 409: duplicate enrollment/attendance or capacity conflict.
- 429: login throttling.
- 500/503: unexpected service/database failure or database readiness failure.

The iOS client should preserve its Keychain credential during network failures and invalidate it only after an authentication failure.
