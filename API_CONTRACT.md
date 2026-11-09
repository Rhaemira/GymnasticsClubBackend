# API contract snapshot

All management routes require `Authorization: Bearer <token>`.

| Method | Path | Request / response |
|---|---|---|
| POST | /auth/login | LoginRequest -> LoginResponse |
| GET | /auth/me | AdminUserResponse |
| POST | /auth/logout | 204 |
| GET | /health | Database readiness JSON |
| GET/POST | /athletes | Athlete[] / Athlete |
| PUT/DELETE | /athletes/:id | Athlete / 200 |
| GET/POST | /coaches | Coach[] / Coach |
| PUT/DELETE | /coaches/:id | Coach / 200 |
| GET/POST | /classes | ClassResponse[] / Class |
| PUT/DELETE | /classes/:id | ClassResponse / 200 |
| GET/POST | /enrollments | EnrollmentResponse[] / EnrollmentResponse |
| DELETE | /enrollments/:id | 200 |
| GET/POST/PUT/DELETE | /attendance | AttendanceResponse[] / AttendanceResponse |
| GET | /reports | ReportsResponse |
| GET | /analytics | AnalyticsResponse |

`CreateClassDTO.coachID` is encoded as `coach_id`; enrollment uses `athlete_id` and `class_id`. Dates are ISO-8601 UTC timestamps. Login, health, and root are public; all business data is protected.
