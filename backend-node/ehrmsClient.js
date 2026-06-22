// ============================================================
//  EHRMS API client
//  Thin HTTP wrapper around the EHRMS backend (the single source
//  of truth for attendance + breaks). Only the face project may
//  change, so we talk to EHRMS exactly as its mobile app does:
//  login -> Bearer token -> /api/attendance + /api/breaks.
// ============================================================

const EHRMS_BASE_URL = (process.env.EHRMS_BASE_URL || 'http://127.0.0.1:9001').replace(/\/+$/, '');
// Web host that serves the staff directory (/api/staff) — separate from the geo/attendance host.
const EHRMS_WEB_BASE_URL = (process.env.EHRMS_WEB_BASE_URL || 'https://hrms.askeva.net').replace(/\/+$/, '');

// Node 18+ ships a global fetch; this backend runs on Node 24.
// `base` overrides the host (e.g. the web host for the staff directory).
async function ehrmsRequest(method, path, { token, body, base, extraHeaders } = {}) {
  const root = base || EHRMS_BASE_URL;
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (extraHeaders) Object.assign(headers, extraHeaders);

  let res;
  try {
    res = await fetch(`${root}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    const err = new Error(`EHRMS backend unreachable at ${root} (${e.message})`);
    err.status = 503;
    err.code = 'EHRMS_UNREACHABLE';
    throw err;
  }

  let data = null;
  const text = await res.text();
  if (text) {
    try { data = JSON.parse(text); } catch { data = { raw: text }; }
  }

  if (!res.ok) {
    const msg =
      (data && (data.message || (data.error && data.error.message) || data.detail)) ||
      `EHRMS request failed (HTTP ${res.status})`;
    const err = new Error(msg);
    err.status = res.status;
    err.data = data;
    err.code = 'EHRMS_ERROR';
    throw err;
  }
  return data;
}

module.exports = {
  EHRMS_BASE_URL,
  EHRMS_WEB_BASE_URL,
  // Auth — returns { success, data: { user, accessToken, refreshToken } }
  login: (email, password) =>
    ehrmsRequest('POST', '/api/auth/login', { body: { email, password } }),

  // --- Web host (staff directory) ---
  // Login against the web host (where /api/staff lives). Used by the directory service account.
  webLogin: (email, password) =>
    ehrmsRequest('POST', '/api/auth/login', { base: EHRMS_WEB_BASE_URL, body: { email, password } }),
  // Full staff directory (admin/HR token required; employee tokens see only themselves).
  getStaffDirectory: (token) =>
    ehrmsRequest('GET', '/api/staff', { base: EHRMS_WEB_BASE_URL, token }),
  refresh: (refreshToken) =>
    ehrmsRequest('POST', '/api/auth/refresh', { body: { refreshToken } }),

  // CANONICAL 1-to-many identify against EHRMS's shared Staff.faceEnrollEmbeddings.
  // The kiosk authenticates with a shared secret (FACE_KIOSK_SECRET), not a staff
  // token. Returns { matched, employee_id?, employee_name?, email?, confidence, reason? }.
  // So the kiosk recognizes faces off the SAME enrollment the EHRMS app validates against.
  identifyFace: (imageBase64, businessId) =>
    ehrmsRequest('POST', '/api/attendance/identify-face', {
      extraHeaders: { 'x-face-kiosk-secret': process.env.FACE_KIOSK_SECRET || '' },
      body: { image_base64: imageBase64, business_id: businessId || undefined },
    }),

  // Face-app dashboard: EHRMS-enrolled employee roster + per-employee full detail
  // (profile + today + month). Kiosk-secret gated; no per-employee token needed.
  enrolledEmployees: (businessId) =>
    ehrmsRequest('GET', `/api/attendance/kiosk-enrolled${businessId ? `?business_id=${encodeURIComponent(businessId)}` : ''}`, {
      extraHeaders: { 'x-face-kiosk-secret': process.env.FACE_KIOSK_SECRET || '' },
    }),
  employeeDetail: (employeeId) =>
    ehrmsRequest('GET', `/api/attendance/kiosk-employee/${encodeURIComponent(employeeId)}`, {
      extraHeaders: { 'x-face-kiosk-secret': process.env.FACE_KIOSK_SECRET || '' },
    }),

  // Enroll the staff's CANONICAL face (Staff.faceEnrollEmbeddings) — the same store the
  // kiosk identifies against. Token-protected: it enrolls the staff that owns `token`.
  // Returns { success, samples, avatar, message }.
  enrollFace: (token, selfies) =>
    ehrmsRequest('POST', '/api/auth/enroll-face', {
      token,
      body: { selfies: Array.isArray(selfies) ? selfies : [selfies] },
    }),

  // Face-app admin: clear a staff's canonical face enrollment (kiosk-secret gated).
  // Looked up by employee_id or email. Returns { success, employee_id, name, cleared }.
  clearFace: ({ employeeId, email }) =>
    ehrmsRequest('POST', '/api/attendance/kiosk-clear-face', {
      extraHeaders: { 'x-face-kiosk-secret': process.env.FACE_KIOSK_SECRET || '' },
      body: { employee_id: employeeId || undefined, email: email || undefined },
    }),

  // Attendance — token-protected (resolves the staff from the Bearer token)
  getToday: (token) =>
    ehrmsRequest('GET', '/api/attendance/today', { token }),
  // One month of attendance (per-day records incl. embedded break details + stats).
  getMonth: (token, year, month) =>
    ehrmsRequest('GET', `/api/attendance/month?year=${year}&month=${month}`, { token }),
  checkIn: (token, body) =>
    ehrmsRequest('POST', '/api/attendance/checkin', { token, body }),
  checkOut: (token, body) =>
    ehrmsRequest('PUT', '/api/attendance/checkout', { token, body }),

  // Breaks — token-protected
  getCurrentBreak: (token) =>
    ehrmsRequest('GET', '/api/breaks/current', { token }),
  // Authoritative daily break list -> { success, data: { breaks: [{ startTime, endTime, ongoing, ... }], ... } }
  getTodayBreaks: (token) =>
    ehrmsRequest('GET', '/api/breaks/today', { token }),
  startBreak: (token, body) =>
    ehrmsRequest('POST', '/api/breaks/start', { token, body }),
  endBreak: (token, id, body) =>
    ehrmsRequest('PATCH', `/api/breaks/${id}/end`, { token, body }),

  // Download any image URL (e.g. a staff avatar) and return raw base64 (no data: prefix).
  fetchImageAsBase64: async (url) => {
    let res;
    try {
      res = await fetch(url);
    } catch (e) {
      const err = new Error(`Could not download image: ${e.message}`);
      err.status = 502; throw err;
    }
    if (!res.ok) {
      const err = new Error(`Image download failed (HTTP ${res.status})`);
      err.status = res.status; throw err;
    }
    const buf = Buffer.from(await res.arrayBuffer());
    return buf.toString('base64');
  },

  // Push a base64 image to EHRMS as the staff's profile photo (multipart 'file').
  // So EHRMS and the face kiosk end up sharing one reference photo.
  uploadProfilePhoto: async (token, base64, filename = 'face.jpg') => {
    const clean = String(base64).replace(/^data:image\/\w+;base64,/, '');
    const buf = Buffer.from(clean, 'base64');
    const form = new FormData();
    form.append('file', new Blob([buf], { type: 'image/jpeg' }), filename);
    let res;
    try {
      res = await fetch(`${EHRMS_BASE_URL}/api/auth/profile-photo`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: form,
      });
    } catch (e) {
      const err = new Error(`EHRMS profile-photo upload unreachable: ${e.message}`);
      err.status = 503; throw err;
    }
    const text = await res.text();
    let data = null; if (text) { try { data = JSON.parse(text); } catch { data = { raw: text }; } }
    if (!res.ok) {
      const msg = (data && (data.message || (data.error && data.error.message))) || `Profile-photo upload failed (HTTP ${res.status})`;
      const err = new Error(msg); err.status = res.status; err.data = data; throw err;
    }
    return data; // { success, data: { photoUrl } }
  },
};
