// Face-recognition backend (biometric match / enroll / link / cross-user verify).
// LOCAL DEV (current): the backend runs on this machine; use its LAN IP. Update if
// the IP changes (`ipconfig`). Phone must be on the same Wi-Fi.
const String kBackendUrl = 'http://192.168.0.26:8000/api';

// AFTER the server deploy, switch to the face app's own domain (no LAN IP, stable HTTPS):
// const String kBackendUrl = 'https://eface.askeva.io/api';

// The EHRMS backend the app punches/breaks against DIRECTLY (single source of truth).
// ALWAYS the DEV server (ehrms.askeva.net = EHRMS's development host) — never the
// production host (app.ektahr.com) and never the value returned by the face backend,
// so a stale/empty ehrms_base_url can never break or mis-route attendance writes.
const String kEhrmsBaseUrl = 'https://ehrms.askeva.net';
