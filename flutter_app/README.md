# Face Biometric — Flutter Mobile App

A Flutter rewrite of the face-recognition attendance mobile app (formerly the
Expo/React Native app in `mobile_app/`). It talks to the Express backend in
`backend-node/`.

## Screens

- **Splash** → auto-redirects to **Login** after 2.5s.
- **Login / Sign Up** — local in-memory admin accounts (default `temp@mail` / `123`).
- **Scanner** — front camera + GPS, auto-scans every 2.5s and calls
  `POST /api/attendance/scan-mobile`. Shows the matched employee card with
  Take a Break / Punch Out / End Break actions.
- **Sidebar** (hamburger menu) — Dashboard, Admin Panel, Logout.
- **Passcode** — 4-digit admin PIN (`1234`) to unlock the Admin Panel.
- **Admin → Enroll User** — capture a face and call
  `POST /api/employees/enroll-face-mobile`.
- **Admin → Registry** — lists enrolled users from attendance records, with
  delete via `DELETE /api/employees/delete`.
- **Dashboard** — stats from `GET /api/employees/metrics` and grouped daily
  logs from `GET /api/attendance/records`.

## Setup

1. Point the app at your backend by editing `lib/config.dart`:
   ```dart
   const String kBackendUrl = 'http://<YOUR_LAN_IP>:8000/api';
   ```
   Use your computer's LAN IP (not `localhost`) when running on a physical
   device or emulator so it can reach the Express server in `backend-node/`.

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on a connected device/emulator:
   ```bash
   flutter run
   ```

## Building an APK

```bash
flutter build apk --release
```

The output APK will be at `build/app/outputs/flutter-apk/app-release.apk`.
