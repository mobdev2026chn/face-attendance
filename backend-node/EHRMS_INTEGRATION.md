# Face ⇄ EHRMS attendance integration

The face kiosk and the EHRMS app are **separate apps with one shared attendance/break
record**. EHRMS is the single source of truth: a punch done at the face kiosk shows up
in EHRMS, and a punch done in the EHRMS app is reflected at the face kiosk. Only the
**face project** was changed — EHRMS is used as-is (no shared secret, no EHRMS edits).

## How it works

1. **Link once** — `POST /api/employees/link-ehrms` with `{ employee_id, ehrms_email,
   ehrms_password }`. The face backend logs into EHRMS (`/api/auth/login`) and stores the
   returned `accessToken` (~30d) + `refreshToken` (~60d) and the EHRMS user/staff ids on
   the face `Employee` record. Sets `ehrmsLinked = true`.
2. **Scan** — on a face match in `/api/attendance/scan-mobile`:
   - **Linked employee** → `handleEhrmsScan` drives EHRMS:
     - reads `GET /api/attendance/today` + `GET /api/breaks/current` for current state,
     - resolves the action (`auto` → in / Already-Checked-In / On-Break-Scan / Punch-Completed),
     - writes via `POST /api/attendance/checkin`, `PUT /api/attendance/checkout`,
       `POST /api/breaks/start`, `PATCH /api/breaks/:id/end` (`source: "software"`),
     - returns the **same response shape** the Flutter app already consumes
       (`action`, `status`, `check_in_time`, `check_out_time`, `already_checked_in`, ...).
   - **Unlinked employee** → unchanged local `AttendanceLog` behaviour (fallback).
3. **Token self-heal** — a 401 from EHRMS triggers a transparent `POST /api/auth/refresh`
   using the stored refresh token; rotated tokens are persisted. If refresh fails, the
   face app is told to re-link the employee.

The face scan image is sent to EHRMS as the punch/break `selfie` (EHRMS accepts raw
base64; the upload is deferred and failure-tolerant, so it never blocks the punch).

## Config

`backend-node/.env`:

```
EHRMS_BASE_URL=http://127.0.0.1:9001   # the running EHRMS API
```

## Endpoints added (face backend)

| Method | Path                              | Body                                              |
|--------|-----------------------------------|---------------------------------------------------|
| POST   | `/api/employees/link-ehrms`       | `{ employee_id, ehrms_email, ehrms_password }`    |
| POST   | `/api/employees/unlink-ehrms`     | `{ employee_id }`                                 |

## Notes / EHRMS-side requirements

EHRMS enforces its own rules on check-in; these surface to the face app as the error
`detail`. For a linked punch to succeed in EHRMS the staff must have **salary configured**
and a **shift assigned**, and must pass any **geofence/geolocation** rule on their
attendance template. Late/early/fine logic is computed by EHRMS, not the face backend.

Files: `ehrmsClient.js` (HTTP client), `server.js` (`handleEhrmsScan`, `ehrmsCall`,
link/unlink routes, scan branch), `models.js` + `db_helper.js` (EHRMS link fields,
`Employee.updateOne`).
