// Replace with your backend computer's LAN IP address when running on a physical device!
// (This machine's current LAN IP — update if it changes; check with `ipconfig`.)
// This is the LOCAL face-recognition backend only (biometric match / enroll / link).
const String kBackendUrl = 'http://10.186.247.215:8000/api';

// The EHRMS backend the app punches/breaks against DIRECTLY (single source of truth).
// ALWAYS the DEV server (ehrms.askeva.net = EHRMS's development host) — never the
// production host (app.ektahr.com) and never the value returned by the face backend,
// so a stale/empty ehrms_base_url can never break or mis-route attendance writes.
const String kEhrmsBaseUrl = 'https://ehrms.askeva.net';
