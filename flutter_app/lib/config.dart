// Face-recognition backend (biometric match / enroll / link / cross-user verify).
// DEV SERVER (current): the deployed face backend on its own domain — stable HTTPS,
// no LAN IP, works off any network (phone need not share the PC's Wi-Fi).
const String kBackendUrl = 'https://eface.askeva.io/api';

// LOCAL DEV fallback: backend running on this machine via its LAN IP (run `ipconfig`
// to get it; phone must be on the same Wi-Fi). Uncomment to point at a local backend.
// const String kBackendUrl = 'http://192.168.0.28:8080/api';

// The EHRMS backend the app punches/breaks against DIRECTLY (single source of truth).
// ALWAYS the DEV server (ehrms.askeva.net = EHRMS's development host) — never the
// production host (app.ektahr.com) and never the value returned by the face backend,
// so a stale/empty ehrms_base_url can never break or mis-route attendance writes.
const String kEhrmsBaseUrl = 'https://ehrms.askeva.net';
