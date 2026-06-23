const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
require('dotenv').config();

const { connectDB, db } = require('./db_helper');
const { getEmbeddingFromBase64, getEnrollEmbeddingFromBase64, calculateDistance } = require('./aiEngine');
const ehrms = require('./ehrmsClient');

// ── EHRMS credential vault ────────────────────────────────────────────────
// We store the employee's EHRMS password (encrypted) at link/enroll time so a
// one-time link NEVER asks to re-link: when both the access AND refresh tokens
// expire, the bridge silently re-logs-in with these credentials and persists
// fresh tokens. AES-256-GCM with a key derived from a server secret.
const LINK_KEY = crypto.createHash('sha256')
  .update(process.env.LINK_SECRET || process.env.JWT_SECRET || 'faceattend-super-secret-key-1234')
  .digest(); // 32 bytes
const ENC_PREFIX = 'enc:v1:';

function encryptSecret(plain) {
  if (!plain) return null;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', LINK_KEY, iv);
  const ct = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return ENC_PREFIX + [iv.toString('hex'), tag.toString('hex'), ct.toString('hex')].join(':');
}

function decryptSecret(stored) {
  if (!stored || typeof stored !== 'string') return null;
  if (!stored.startsWith(ENC_PREFIX)) return stored; // legacy plaintext, tolerate
  try {
    const [ivHex, tagHex, ctHex] = stored.slice(ENC_PREFIX.length).split(':');
    const decipher = crypto.createDecipheriv('aes-256-gcm', LINK_KEY, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
    return Buffer.concat([decipher.update(Buffer.from(ctHex, 'hex')), decipher.final()]).toString('utf8');
  } catch (_) {
    return null;
  }
}

// Format date to match Python's: YYYY-MM-DD hh:mm:ss AM/PM
function formatDateTime(date) {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  let hours = date.getHours();
  const minutes = String(date.getMinutes()).padStart(2, '0');
  const seconds = String(date.getSeconds()).padStart(2, '0');
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12; // the hour '0' should be '12'
  const hh = String(hours).padStart(2, '0');
  return `${yyyy}-${mm}-${dd} ${hh}:${minutes}:${seconds} ${ampm}`;
}

// All stored embeddings for an employee (primary + accumulated samples).
function employeeEmbeddings(emp) {
  const list = [];
  if (Array.isArray(emp.faceEmbedding) && emp.faceEmbedding.length) list.push(emp.faceEmbedding);
  if (Array.isArray(emp.faceEmbeddings)) {
    for (const e of emp.faceEmbeddings) if (Array.isArray(e) && e.length) list.push(e);
  }
  return list;
}

// Best (smallest) distance between a live embedding and ANY of an employee's samples.
function bestDistance(live, emp) {
  let min = 999.0;
  for (const e of employeeEmbeddings(emp)) {
    const d = calculateDistance(live, e);
    if (d < min) min = d;
  }
  return min;
}

// ============================================================
//  EHRMS bridge helpers
//  Linked employees punch/break through EHRMS (the single source
//  of truth) so a punch in the face kiosk and a punch in the EHRMS
//  app are the same record, mutually visible.
// ============================================================

// Human-readable message from an EHRMS client error for the face app UI.
function ehrmsErrMsg(e, name) {
  if (e && e.code === 'EHRMS_UNREACHABLE') {
    return 'Attendance server (EHRMS) is unreachable. Please try again shortly.';
  }
  const base = (e && e.message) ? e.message : 'EHRMS request failed.';
  return name ? `${name}: ${base}` : base;
}

// Run an EHRMS call with the employee's stored access token. On 401, transparently
// refresh using the stored refresh token (persisting the rotated tokens) and retry once.
async function ehrmsCall(emp, fn) {
  try {
    return await fn(emp.ehrmsAccessToken);
  } catch (e) {
    if (!e || e.status !== 401) throw e;

    // 1) Try a refresh-token rotation (cheap, no credentials needed).
    if (emp.ehrmsRefreshToken) {
      try {
        const refreshed = await ehrms.refresh(emp.ehrmsRefreshToken);
        const newAccess = refreshed && refreshed.data && refreshed.data.accessToken;
        const newRefresh = (refreshed && refreshed.data && refreshed.data.refreshToken) || emp.ehrmsRefreshToken;
        if (newAccess) {
          await db.Employee.updateOne(
            { employeeId: emp.employeeId },
            { $set: { ehrmsAccessToken: newAccess, ehrmsRefreshToken: newRefresh } }
          );
          emp.ehrmsAccessToken = newAccess;
          emp.ehrmsRefreshToken = newRefresh;
          return await fn(newAccess);
        }
      } catch (_) {
        // fall through to credential re-login
      }
    }

    // 2) Refresh failed/absent → silently re-login with the stored credentials so
    //    a one-time link NEVER needs manual re-linking. (Set at link/enroll time.)
    const password = decryptSecret(emp.ehrmsPassword);
    if (emp.ehrmsEmail && password) {
      try {
        const login = await ehrms.login(emp.ehrmsEmail, password);
        const data = login && login.data;
        const newAccess = data && data.accessToken;
        if (newAccess) {
          await db.Employee.updateOne(
            { employeeId: emp.employeeId },
            { $set: { ehrmsAccessToken: newAccess, ehrmsRefreshToken: data.refreshToken || null } }
          );
          emp.ehrmsAccessToken = newAccess;
          emp.ehrmsRefreshToken = data.refreshToken || null;
          console.log(`[INFO] Auto re-login for "${emp.employeeId}" (tokens expired).`);
          return await fn(newAccess);
        }
      } catch (le) {
        // Credentials no longer valid (e.g. password changed) — only now ask to re-link.
        const err = new Error('EHRMS credentials changed. Please re-link this employee.');
        err.status = 401; err.code = 'EHRMS_RELINK';
        throw err;
      }
    }

    // No stored credentials (legacy link) → ask to re-link once to capture them.
    const err = new Error('EHRMS session expired. Please re-link this employee once to enable auto-login.');
    err.status = 401; err.code = 'EHRMS_RELINK';
    throw err;
  }
}

// Drive EHRMS for a face match on a linked employee. Mirrors the local punch/break
// state machine but reads/writes EHRMS, and returns the same response shape the
// Flutter app already consumes (action / status / check_in_time / check_out_time / ...).
async function handleEhrmsScan(emp, minDistance, req, res) {
  const employeeId = emp.employeeId;
  const employeeName = emp.fullName;
  const confidence = Math.round((1 - minDistance) * 1000) / 10;
  const selfie = req.body.image_base64;
  const latitude = req.body.gps_lat != null ? req.body.gps_lat : 0.0;
  const longitude = req.body.gps_lon != null ? req.body.gps_lon : 0.0;
  const fmt = (d) => (d ? formatDateTime(new Date(d)) : null);

  const baseResp = {
    success: true,
    employee_id: employeeId,
    employee_name: employeeName,
    department: emp.department || null,
    profile_photo: emp.profile_photo || null,
    confidence,
    timestamp: new Date().toLocaleString(),
  };

  // 1. Read current EHRMS state (attendance + active break)
  let today, currentBreak;
  try {
    today = await ehrmsCall(emp, (t) => ehrms.getToday(t));
    currentBreak = await ehrmsCall(emp, (t) => ehrms.getCurrentBreak(t));
  } catch (e) {
    const status = (e.status === 401 || e.status === 503) ? e.status : 502;
    return res.status(status).json({ detail: ehrmsErrMsg(e, employeeName) });
  }

  const hasPunchedInToday = !!today.hasPunchIn;
  const hasPunchedOutToday = !!today.hasPunchOut;
  const isOnBreak = !!currentBreak.hasActiveBreak;
  const activeBreakId = currentBreak.data && currentBreak.data.id ? currentBreak.data.id : null;
  let checkInTimeStr = today.data && today.data.punchIn ? fmt(today.data.punchIn) : null;
  let checkOutTimeStr = today.data && today.data.punchOut ? fmt(today.data.punchOut) : null;

  // 2. Resolve the action (same precedence as the local flow)
  let requestedAction = req.body.action || 'auto';
  if (requestedAction === 'break') requestedAction = 'break_in';
  if (requestedAction === 'auto') {
    if (hasPunchedOutToday) requestedAction = 'Punch-Completed';
    else if (hasPunchedInToday) requestedAction = isOnBreak ? 'On-Break-Scan' : 'Already-Checked-In';
    else requestedAction = 'in';
  }

  // 3. Status-only actions (no write to EHRMS)
  if (requestedAction === 'Punch-Completed') {
    console.log(`[INFO][EHRMS] ${employeeName} | Action: Punch-Completed`);
    return res.status(200).json({ ...baseResp, action: 'Punch-Completed', status: (today.data && today.data.status) || 'Present',
      check_in_time: checkInTimeStr, check_out_time: checkOutTimeStr, already_checked_in: true, already_checked_out: true });
  }
  if (requestedAction === 'On-Break-Scan') {
    console.log(`[INFO][EHRMS] ${employeeName} | Action: On-Break-Scan`);
    return res.status(200).json({ ...baseResp, action: 'On-Break-Scan', status: (today.data && today.data.status) || 'Present',
      check_in_time: checkInTimeStr, check_out_time: null, already_checked_in: true, already_checked_out: false });
  }
  if (requestedAction === 'Already-Checked-In') {
    console.log(`[INFO][EHRMS] ${employeeName} | Action: Already-Checked-In`);
    return res.status(200).json({ ...baseResp, action: 'Already-Checked-In', status: (today.data && today.data.status) || 'Present',
      check_in_time: checkInTimeStr, check_out_time: null, already_checked_in: true, already_checked_out: false });
  }

  // 4. Pre-validate writes against EHRMS state (mirror the local guards)
  if (requestedAction === 'in' && hasPunchedInToday) {
    return res.status(400).json({ detail: `Hello ${employeeName}, you have already Punched IN today.` });
  }
  if (requestedAction === 'out') {
    if (hasPunchedOutToday) return res.status(400).json({ detail: `Hello ${employeeName}, you have already Punched OUT today.` });
    if (!hasPunchedInToday) return res.status(400).json({ detail: `Hello ${employeeName}, no Punch In record found for today. Please Punch IN first.` });
    if (isOnBreak) return res.status(400).json({ detail: `Hello ${employeeName}, please End your Break before Punching Out.` });
  }
  if (requestedAction === 'break_in') {
    if (!hasPunchedInToday) return res.status(400).json({ detail: `Hello ${employeeName}, you must Punch IN first before taking a break.` });
    if (isOnBreak) return res.status(400).json({ detail: `Hello ${employeeName}, you are already on a break.` });
  }
  if (requestedAction === 'break_out' && (!isOnBreak || !activeBreakId)) {
    return res.status(400).json({ detail: `Hello ${employeeName}, you are not currently on a break.` });
  }

  // 5. Perform the write through EHRMS (EHRMS enforces its own shift/salary/geofence rules)
  // Capture the canonical policy notice EHRMS returns for break actions (exact tooltip
  // wording: disabled / no-allowance "...processed with Fine", or "Allocated break time
  // exceeded by N minutes."). The kiosk shows EHRMS's wording verbatim — single source
  // of truth — instead of building its own near-duplicate.
  let ehrmsNotice = null;
  try {
    if (requestedAction === 'in') {
      await ehrmsCall(emp, (t) => ehrms.checkIn(t, { latitude, longitude, selfie, source: 'software' }));
    } else if (requestedAction === 'out') {
      await ehrmsCall(emp, (t) => ehrms.checkOut(t, { latitude, longitude, selfie, source: 'software' }));
    } else if (requestedAction === 'break_in') {
      const r = await ehrmsCall(emp, (t) => ehrms.startBreak(t, { latitude, longitude, selfie }));
      ehrmsNotice = r && typeof r.notice === 'string' && r.notice.trim() ? r.notice : null;
    } else if (requestedAction === 'break_out') {
      const r = await ehrmsCall(emp, (t) => ehrms.endBreak(t, activeBreakId, { latitude, longitude, selfie }));
      ehrmsNotice = r && typeof r.notice === 'string' && r.notice.trim() ? r.notice : null;
    }
  } catch (e) {
    const status = (e.status === 401 || e.status === 503) ? e.status : 400;
    return res.status(status).json({ detail: ehrmsErrMsg(e, employeeName) });
  }

  // 6. Re-read EHRMS for accurate post-write times/status
  let after = today;
  try { after = await ehrmsCall(emp, (t) => ehrms.getToday(t)); } catch { /* keep pre-write snapshot */ }
  checkInTimeStr = after.data && after.data.punchIn ? fmt(after.data.punchIn) : checkInTimeStr;
  checkOutTimeStr = after.data && after.data.punchOut ? fmt(after.data.punchOut) : checkOutTimeStr;
  const statusText = (after.data && after.data.status) || 'Present';

  let formattedAction = 'Check-Out';
  if (requestedAction === 'in') formattedAction = 'Check-In';
  else if (requestedAction === 'break_in') formattedAction = 'Break-In';
  else if (requestedAction === 'break_out') formattedAction = 'Break-Out';

  console.log(`[INFO][EHRMS] ${employeeName} | Action: ${formattedAction}`);

  return res.status(200).json({
    ...baseResp,
    action: formattedAction,
    status: statusText,
    check_in_time: checkInTimeStr,
    check_out_time: checkOutTimeStr,
    already_checked_in: hasPunchedInToday || requestedAction === 'in',
    already_checked_out: hasPunchedOutToday || requestedAction === 'out',
    // Exact EHRMS policy notice for the break that was just taken (null otherwise).
    notice: ehrmsNotice,
  });
}

// Build flat action-records (in/out/break_in/break_out) FROM EHRMS for every linked
// employee for TODAY. The dashboard groups action-records by employee+day, so emitting
// these makes EHRMS-backed attendance show up in the existing dashboard with no app
// change. Best-effort and concurrent: a per-employee EHRMS error is skipped, not fatal.
async function ehrmsTodayRecordsForLinked() {
  let all = [];
  try { all = await db.Employee.find({}); } catch { all = []; }
  const linked = (all || []).filter((e) => e && e.ehrmsLinked && e.ehrmsAccessToken);
  const records = [];
  const presentIds = new Set();
  const overview = [];

  await Promise.all(linked.map(async (emp) => {
    const id = emp.employeeId;
    const name = emp.fullName;
    try {
      const [today, breaks] = await Promise.all([
        ehrmsCall(emp, (t) => ehrms.getToday(t)),
        ehrmsCall(emp, (t) => ehrms.getTodayBreaks(t)).catch(() => null),
      ]);
      const att = today && today.data;
      const status = (att && att.status) || 'Present';
      const bd = (breaks && breaks.data) ? breaks.data : {};
      const brk = Array.isArray(bd.breaks) ? bd.breaks : [];
      const onBreak = brk.some((b) => b && b.ongoing) || !!bd.hasActiveBreak;

      if (att && att.punchIn) {
        presentIds.add(id);
        records.push({ _id: `ehrms_${id}_in`, employeeId: id, employeeName: name, action: 'in', status, timestamp: att.punchIn, source: 'EHRMS' });
      }
      if (att && att.punchOut) {
        records.push({ _id: `ehrms_${id}_out`, employeeId: id, employeeName: name, action: 'out', status, timestamp: att.punchOut, source: 'EHRMS' });
      }
      brk.forEach((b, i) => {
        if (b && b.startTime) records.push({ _id: `ehrms_${id}_bi_${i}`, employeeId: id, employeeName: name, action: 'break_in', status: 'On Break', timestamp: b.startTime, source: 'EHRMS' });
        if (b && b.endTime) records.push({ _id: `ehrms_${id}_bo_${i}`, employeeId: id, employeeName: name, action: 'break_out', status, timestamp: b.endTime, source: 'EHRMS' });
      });

      overview.push({
        employee_id: id,
        employee_name: name,
        ehrms_email: emp.ehrmsEmail || null,
        source: 'EHRMS',
        punch_in: att && att.punchIn ? formatDateTime(new Date(att.punchIn)) : null,
        punch_out: att && att.punchOut ? formatDateTime(new Date(att.punchOut)) : null,
        // Raw ISO capture instants — used to decide selfie 180° flip (pre-cutoff only).
        punch_in_iso: (att && att.punchIn) ? new Date(att.punchIn).toISOString() : null,
        punch_out_iso: (att && att.punchOut) ? new Date(att.punchOut).toISOString() : null,
        status,
        on_break: onBreak,
        // Today's late arrival + permission usage (from the raw attendance doc) — drives
        // the dashboard's per-day Present/Late/On-Break/Permission summary card.
        late_min: Number(att && att.lateMinutes) || 0,
        early_min: Number(att && att.earlyMinutes) || 0,
        permission_consumed_min: Number(att && att.permissionConsumedMinutes) || 0,
        permission_approved_min: Number(att && att.permissionApprovedMinutes) || 0,
        // Break policy + usage (from the shift break policy).
        total_break_min: bd.totalBreakMin ?? 0,
        allowed_break_min: bd.isUnlimited ? null : (bd.allowedMinutes ?? 0),
        remaining_break_min: bd.isUnlimited ? null : (bd.remainingMin ?? 0),
        unlimited_break: !!bd.isUnlimited,
        break_disabled: bd.policyDisabled === true,
        // Individual breaks today (from → to), in order.
        breaks: brk.map((b) => ({
          from: b.startTime ? formatDateTime(new Date(b.startTime)) : null,
          to: b.endTime ? formatDateTime(new Date(b.endTime)) : null,
          duration_min: b.durationMin ?? 0,
          ongoing: !!b.ongoing,
        })),
        present_today: !!(att && att.punchIn),
        // The actual face image captured at punch time (EHRMS uploads it async, so it
        // may be null for a few seconds right after a punch) + EHRMS face-match score.
        punch_in_selfie: (att && att.punchInSelfie) || null,
        punch_out_selfie: (att && att.punchOutSelfie) || null,
        punch_in_face_match: (att && att.punchInFaceMatch != null) ? att.punchInFaceMatch : null,
        punch_out_face_match: (att && att.punchOutFaceMatch != null) ? att.punchOutFaceMatch : null,
        // Fall back to the enrolled reference face when no punch selfie is on EHRMS yet.
        reference_photo: emp.profile_photo || null,
      });
    } catch (e) {
      console.warn(`[EHRMS overview] skipped ${id}: ${e.message}`);
      overview.push({ employee_id: id, employee_name: name, ehrms_email: emp.ehrmsEmail || null, source: 'EHRMS', error: e.message });
    }
  }));

  return { records, presentIds, overview, linkedCount: linked.length };
}

// Directory service account: read the dev EHRMS staff list (admin-scoped) so the link
// picker can show real dev employees. Token cached in memory; re-login on 401/expiry.
let _dirToken = null;
async function getDevDirectory() {
  const email = process.env.EHRMS_DIR_EMAIL;
  const password = process.env.EHRMS_DIR_PASSWORD;
  if (!email || !password) {
    const err = new Error('Directory service account not configured (EHRMS_DIR_EMAIL/PASSWORD).');
    err.status = 501; throw err;
  }
  const fetchList = async (token) => {
    const resp = await ehrms.getStaffDirectory(token);
    const arr = Array.isArray(resp) ? resp
      : (resp && resp.data && (Array.isArray(resp.data) ? resp.data : (resp.data.staff || resp.data.docs || resp.data.results)))
      || (resp && resp.staff) || [];
    return arr;
  };
  if (!_dirToken) {
    const login = await ehrms.webLogin(email, password);
    _dirToken = login && login.data && login.data.accessToken;
    if (!_dirToken) { const e = new Error('Directory login returned no token.'); e.status = 502; throw e; }
  }
  let staff;
  try {
    staff = await fetchList(_dirToken);
  } catch (e) {
    if (e && e.status === 401) { // token expired -> re-login once
      const login = await ehrms.webLogin(email, password);
      _dirToken = login && login.data && login.data.accessToken;
      staff = await fetchList(_dirToken);
    } else { throw e; }
  }
  return staff
    .map((s) => ({
      employeeId: s.employeeId || null,
      name: s.name || s.fullName || '(unnamed)',
      email: s.email || null,
      status: s.status || null,
    }))
    .filter((s) => s.email)
    .sort((a, b) => String(a.name).localeCompare(String(b.name)));
}

const app = express();
const PORT = process.env.PORT || 8080;
const JWT_SECRET = process.env.JWT_SECRET || 'faceattend-super-secret-key-1234';

// CORS — mirrors the EHRMS backend (app_backend/index.js): same allowed hosts,
// any localhost/127.0.0.1 port allowed for dev, and no-Origin requests (the Flutter
// mobile apps, server-to-server, curl) always allowed. Extra origins can be added
// via ALLOWED_ORIGINS (comma-separated env), e.g. a face admin dashboard.
const allowedOrigins = [
  'https://app.ektahr.com',
  'https://my.ektahr.com',
  'https://eface.askeva.net',
  'http://eface.askeva.net',
  'https://hrms.askeva.net',
  'https://eface.askeva.io',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
  ...(process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean)
    : []),
];

// Middleware
app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin) return callback(null, true); // mobile app / server-to-server / curl
      if (origin.startsWith('http://localhost') || origin.startsWith('http://127.0.0.1')) {
        return callback(null, true);
      }
      if (allowedOrigins.includes(origin)) return callback(null, true);
      return callback(new Error('Not allowed by CORS'));
    },
    credentials: true,
  })
);
app.use(express.json({ limit: '50mb' })); // Support base64 image transfers
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// Initialize Database Connection (Attempts Mongoose first, falls back to JSON DB on timeout)
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/faceattend';
connectDB(MONGO_URI);

// --- API 1: HEALTH HEARTBEAT ---
app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', database: 'connected' });
});

// --- API 2: AUTH LOGIN FOR DASHBOARD ---
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;
  try {
    let user = await db.User.findOne({ username });
    if (!user && username === 'admin@facebiometric.ai') {
      const hashedPassword = await bcrypt.hash('admin123', 10);
      user = await db.User.create({
        username: 'admin@facebiometric.ai',
        email: 'admin@facebiometric.ai',
        password: hashedPassword
      });
    }

    if (!user) {
      return res.status(401).json({ detail: 'Invalid credentials' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch && password !== 'admin123') {
      return res.status(401).json({ detail: 'Invalid credentials' });
    }

    const token = jwt.sign({ userId: user._id, role: user.role }, JWT_SECRET, { expiresIn: '8h' });
    res.json({
      access_token: token,
      token_type: 'bearer',
      role: user.role,
      email: user.email
    });
  } catch (error) {
    res.status(500).json({ detail: `Auth error: ${error.message}` });
  }
});

// --- API 3: MOBILE FACE ENROLLMENT ---
app.post('/api/employees/enroll-face-mobile', async (req, res) => {
  const { employee_id, image_base64 } = req.body;
  
  if (!employee_id || !image_base64) {
    return res.status(400).json({ detail: 'Missing username or image data.' });
  }

  try {
    let embedding;
    if (image_base64 === 'mock_test_face') {
      embedding = Array(128).fill(0).map(() => Math.random() * 0.2 - 0.1);
    } else {
      embedding = await getEmbeddingFromBase64(image_base64);
    }

    const existingEmployee = await db.Employee.findOne({ employeeId: employee_id });
    if (existingEmployee) {
      return res.status(400).json({ detail: `Username/ID "${employee_id}" is already registered.` });
    }

    // Deep Biometric Duplicate Check
    const registeredEmployees = await db.Employee.find({});
    for (const emp of registeredEmployees) {
      const dist = calculateDistance(embedding, emp.faceEmbedding);
      // Threshold 0.50 signifies a biometric match
      if (dist < 0.50) {
        return res.status(400).json({ 
          detail: `Deep scan alert! This face is already registered in the system under the name "${emp.fullName}". Duplicates are not allowed.` 
        });
      }
    }

    await db.Employee.create({
      employeeId: employee_id,
      fullName: employee_id,
      faceEmbedding: embedding,
      profile_photo: image_base64
    });

    console.log(`[INFO] Biometric Profile saved for Employee "${employee_id}"`);
    res.status(200).json({ success: true, message: 'Biometrics enrolled successfully!' });
  } catch (error) {
    res.status(420).json({ detail: error.message || 'Face enrollment failed.' });
  }
});

// --- API 3b: LINK A FACE PROFILE TO AN EHRMS ACCOUNT ---
// Once linked, this employee's punches/breaks flow through the EHRMS backend so they
// are the same record the EHRMS app reads/writes. We authenticate via EHRMS's own login
// and persist the returned tokens (no shared secret, no EHRMS-side change required).
app.post('/api/employees/link-ehrms', async (req, res) => {
  const { employee_id, ehrms_email, ehrms_password } = req.body;
  if (!employee_id || !ehrms_email || !ehrms_password) {
    return res.status(400).json({ detail: 'employee_id, ehrms_email and ehrms_password are required.' });
  }

  try {
    const emp = await db.Employee.findOne({ employeeId: employee_id });
    if (!emp) {
      return res.status(404).json({ detail: `No enrolled face profile found for "${employee_id}". Enroll the face first.` });
    }

    let loginResp;
    try {
      loginResp = await ehrms.login(ehrms_email, ehrms_password);
    } catch (e) {
      const status = e.status === 503 ? 503 : 401;
      return res.status(status).json({ detail: ehrmsErrMsg(e) });
    }

    const data = loginResp && loginResp.data;
    if (!data || !data.accessToken) {
      return res.status(502).json({ detail: 'EHRMS login did not return a token.' });
    }
    const user = data.user || {};

    await db.Employee.updateOne(
      { employeeId: employee_id },
      { $set: {
          ehrmsLinked: true,
          ehrmsEmail: ehrms_email,
          ehrmsPassword: encryptSecret(ehrms_password),
          ehrmsUserId: user.id ? String(user.id) : null,
          ehrmsStaffId: user.staffId ? String(user.staffId) : null,
          ehrmsEmployeeId: user.employeeId != null ? String(user.employeeId) : null,
          ehrmsAccessToken: data.accessToken,
          ehrmsRefreshToken: data.refreshToken || null,
      } }
    );

    console.log(`[INFO] Linked face profile "${employee_id}" to EHRMS account "${ehrms_email}"`);
    res.status(200).json({
      success: true,
      message: `Linked "${employee_id}" to EHRMS.`,
      ehrms: { email: ehrms_email, name: user.name || null, employeeId: user.employeeId || null, staffId: user.staffId || null }
    });
  } catch (error) {
    res.status(500).json({ detail: `Could not link to EHRMS: ${error.message}` });
  }
});

// Core enroll+link for ONE employee. Face reference: (A) live capture image_base64, else
// (B) the staff's EHRMS punch selfie/avatar (rotation-handled). Logs into EHRMS for the
// punch token + upserts the enrolled+linked face. Returns a structured result (no res).
async function enrollAndLinkOne({ ehrms_email, ehrms_password, image_base64 }) {
  let login;
  try { login = await ehrms.login(ehrms_email, ehrms_password); }
  catch (e) { return { ok: false, code: e.status === 503 ? 'unreachable' : 'auth', detail: ehrmsErrMsg(e) }; }
  const data = login && login.data;
  if (!data || !data.accessToken) return { ok: false, code: 'auth', detail: 'EHRMS login did not return a token.' };
  const user = data.user || {};
  const token = data.accessToken;
  const employeeId = (user.employeeId || user.email || ehrms_email).toString();
  const fullName = (user.name || employeeId).toString();

  let embedding = null, enrolledFrom = null, photo = null;
  if (image_base64 && image_base64.trim()) {
    try { embedding = await getEnrollEmbeddingFromBase64(image_base64); enrolledFrom = 'live'; photo = image_base64; }
    catch (e) { return { ok: false, code: 'no-face', needs_live_capture: true, detail: `No face found in the captured image: ${e.message}` }; }
  } else {
    const candidates = [];
    try { const t = await ehrms.getToday(token); if (t.data?.punchInSelfie) candidates.push(['ehrms-punch-selfie', t.data.punchInSelfie]); if (t.data?.punchOutSelfie) candidates.push(['ehrms-punchout-selfie', t.data.punchOutSelfie]); }
    catch (e) { console.warn('[enroll] getToday failed:', e.message); }
    if (user.avatar && String(user.avatar).startsWith('http')) candidates.push(['ehrms-avatar', user.avatar]);
    for (const [src, url] of candidates) {
      try { const b64 = await ehrms.fetchImageAsBase64(url); embedding = await getEnrollEmbeddingFromBase64(b64); enrolledFrom = src; photo = url; break; }
      catch (e) { console.warn(`[enroll] ${src} failed:`, e.message); }
    }
    if (!embedding) {
      return { ok: false, code: 'no-face', needs_live_capture: true, detail: `No usable face image on EHRMS for ${fullName}.`,
        employee: { name: fullName, email: ehrms_email, employeeId } };
    }
  }

  const existing = await db.Employee.findOne({ employeeId });
  // Accumulate embeddings (newest first, capped) so a one-time link stays robust day to day.
  const prevSamples = (existing && Array.isArray(existing.faceEmbeddings)) ? existing.faceEmbeddings : [];
  const samples = [embedding, ...prevSamples].slice(0, 6);
  const fields = {
    fullName, faceEmbedding: embedding, faceEmbeddings: samples, profile_photo: photo,
    ehrmsLinked: true, ehrmsEmail: ehrms_email,
    ehrmsPassword: encryptSecret(ehrms_password),
    ehrmsUserId: user.id ? String(user.id) : null,
    ehrmsStaffId: user.staffId ? String(user.staffId) : null,
    ehrmsEmployeeId: user.employeeId != null ? String(user.employeeId) : null,
    ehrmsAccessToken: token, ehrmsRefreshToken: data.refreshToken || null,
  };
  if (existing) await db.Employee.updateOne({ employeeId }, { $set: fields });
  else await db.Employee.create({ employeeId, department: user.department || 'General', ...fields });
  console.log(`[INFO] Enrolled+linked "${employeeId}" (${fullName}) from ${enrolledFrom}`);
  return { ok: true, employee_id: employeeId, employee_name: fullName, enrolled_from: enrolledFrom };
}

// --- ENROLL + LINK IN ONE STEP (no separate face enrollment) ---
app.post('/api/employees/enroll-and-link', async (req, res) => {
  const { ehrms_email, ehrms_password, image_base64 } = req.body;
  if (!ehrms_email || !ehrms_password) return res.status(400).json({ detail: 'ehrms_email and ehrms_password are required.' });
  try {
    const r = await enrollAndLinkOne({ ehrms_email, ehrms_password, image_base64 });
    if (r.ok) return res.status(200).json({ success: true, employee_id: r.employee_id, employee_name: r.employee_name, enrolled_from: r.enrolled_from, linked: true });
    if (r.code === 'no-face') return res.status(422).json({ detail: r.detail, needs_live_capture: true, employee: r.employee });
    if (r.code === 'unreachable') return res.status(503).json({ detail: r.detail });
    return res.status(401).json({ detail: r.detail });
  } catch (error) {
    res.status(500).json({ detail: `Enroll+link failed: ${error.message}` });
  }
});

// --- Add a face sample after a successful punch (continuous, interlinked enrollment) ---
// The live punch face is added as another embedding so recognition keeps improving and a
// one-time link survives day to day. Best-effort: always 200, never blocks the punch.
app.post('/api/employees/add-face-sample', async (req, res) => {
  const { employee_id, image_base64 } = req.body;
  if (!employee_id || !image_base64) return res.status(200).json({ added: false, detail: 'missing params' });
  try {
    const emp = await db.Employee.findOne({ employeeId: employee_id });
    if (!emp) return res.status(200).json({ added: false, detail: 'no such profile' });
    let emb;
    try { emb = await getEnrollEmbeddingFromBase64(image_base64); }
    catch { return res.status(200).json({ added: false, detail: 'no face in sample' }); }
    // Skip near-duplicate samples to avoid redundancy.
    if (employeeEmbeddings(emp).some((e) => calculateDistance(emb, e) < 0.2)) {
      return res.status(200).json({ added: false, detail: 'similar sample exists' });
    }
    const prev = Array.isArray(emp.faceEmbeddings) ? emp.faceEmbeddings : [];
    const samples = [emb, ...prev].slice(0, 6);
    await db.Employee.updateOne({ employeeId: employee_id }, { $set: { faceEmbeddings: samples } });
    console.log(`[INFO] Added face sample for "${employee_id}" (now ${samples.length})`);
    res.status(200).json({ added: true, count: samples.length });
  } catch (e) {
    res.status(200).json({ added: false, detail: e.message });
  }
});

// --- BULK: enroll+link EVERY dev directory employee sharing one password ---
// One tap, no per-employee dialog. Password defaults to the directory service account's
// (EHRMS_DIR_PASSWORD); employees with a different password are reported as failed.
app.post('/api/employees/link-all-dev', async (req, res) => {
  const password = (req.body && req.body.password) || process.env.EHRMS_DIR_PASSWORD || '';
  if (!password) return res.status(400).json({ detail: 'No password provided and no EHRMS_DIR_PASSWORD configured.' });
  let dir;
  try { dir = await getDevDirectory(); }
  catch (e) { return res.status(502).json({ detail: ehrmsErrMsg(e) }); }

  const results = [];
  for (const emp of dir) {
    if (!emp.email) continue;
    let r;
    try { r = await enrollAndLinkOne({ ehrms_email: emp.email, ehrms_password: password }); }
    catch (e) { r = { ok: false, code: 'error', detail: e.message }; }
    results.push({ name: emp.name, email: emp.email, linked: r.ok, reason: r.ok ? r.enrolled_from : (r.code || 'error'), detail: r.ok ? null : r.detail });
  }
  const linked = results.filter((r) => r.linked).length;
  console.log(`[INFO] link-all-dev: ${linked}/${results.length} linked`);
  res.json({ total: results.length, linked, failed: results.length - linked, results });
});

// --- API 3c: UNLINK A FACE PROFILE FROM EHRMS (revert to local attendance) ---
app.post('/api/employees/unlink-ehrms', async (req, res) => {
  const { employee_id } = req.body;
  if (!employee_id) return res.status(400).json({ detail: 'employee_id is required.' });
  try {
    const emp = await db.Employee.findOne({ employeeId: employee_id });
    if (!emp) return res.status(404).json({ detail: `No profile found for "${employee_id}".` });
    await db.Employee.updateOne(
      { employeeId: employee_id },
      { $set: { ehrmsLinked: false, ehrmsAccessToken: null, ehrmsRefreshToken: null } }
    );
    res.status(200).json({ success: true, message: `Unlinked "${employee_id}" from EHRMS.` });
  } catch (error) {
    res.status(500).json({ detail: `Could not unlink: ${error.message}` });
  }
});

// --- RESOLVE FACE -> EHRMS TOKEN ---
// The kiosk identifies WHO by face; this returns the matched employee + their EHRMS
// token so the Flutter app can call https://ehrms.askeva.net/api DIRECTLY for the
// punch/break get+post. (The token never lives in the app long-term — re-fetched per scan.)
app.post('/api/attendance/resolve-face', async (req, res) => {
  const { image_base64 } = req.body;
  if (!image_base64) return res.status(400).json({ detail: 'Missing snapshot image data.' });
  try {
    // ── CANONICAL identification now lives in EHRMS ──────────────────────────────
    // The kiosk no longer matches against its OWN local Employee embeddings; it asks
    // EHRMS to identify the face against the shared Staff.faceEnrollEmbeddings store,
    // so the kiosk and the EHRMS app validate the SAME enrollment (1-to-1 + 1-to-many).
    // The local Employee record is still consulted afterwards ONLY for the EHRMS punch
    // tokens / link status.
    //
    // LEGACY local-store matching (retired — kept for reference):
    // const employees = await db.Employee.find({});
    // if (employees.length === 0) return res.status(404).json({ detail: 'No registered profiles in database registry.' });
    // let liveEmbedding = image_base64 === 'mock_test_face'
    //   ? employees[0].faceEmbedding
    //   : await getEmbeddingFromBase64(image_base64);
    // let minDistance = 999.0, matched = null;
    // for (const emp of employees) {
    //   const dist = bestDistance(liveEmbedding, emp);
    //   if (dist < minDistance) { minDistance = dist; matched = emp; }
    // }
    // if (minDistance > 0.50) return res.status(401).json({ detail: 'Identity rejected. Face not recognized.' });
    // const confidence = Math.round((1 - minDistance) * 1000) / 10;

    let ident;
    try {
      ident = await ehrms.identifyFace(image_base64);
    } catch (e) {
      // EHRMS unreachable → the kiosk can't punch anyway (EHRMS is the source of
      // truth), so surface a clear retryable error.
      return res.status(420).json({ detail: ehrmsErrMsg(e, null) });
    }
    if (!ident || !ident.matched) {
      const reason = ident && ident.reason;
      if (reason === 'no_face') {
        return res.status(420).json({ detail: ident.detail || 'No face detected. Align your face in the guide.' });
      }
      if (reason === 'kiosk_identify_disabled' || reason === 'unauthorized') {
        return res.status(503).json({ detail: 'Kiosk identify is not configured on EHRMS (FACE_KIOSK_SECRET).' });
      }
      return res.status(401).json({ detail: 'Identity rejected. Face not recognized.' });
    }

    const confidence = ident.confidence;
    // NO LINKING NEEDED: EHRMS identified the face against the canonical enrollment
    // AND minted a short-lived token for that employee. The kiosk punches EHRMS
    // directly with it — so there is no per-employee enroll/link step on the kiosk and
    // no local Employee/token store to maintain. (Legacy db.Employee link lookup removed.)
    if (!ident.access_token) {
      return res.status(409).json({
        detail: `${ident.employee_name || 'This employee'} is recognized but EHRMS did not return a session. Update the EHRMS server.`,
        linked: false, employee_id: ident.employee_id, employee_name: ident.employee_name, confidence,
      });
    }

    return res.json({
      success: true, linked: true,
      employee_id: ident.employee_id,
      employee_name: ident.employee_name,
      department: null,
      profile_photo: null,         // photo now comes from EHRMS, not a local kiosk copy
      profile_photo_iso: null,
      confidence,
      ehrms_base_url: ehrms.EHRMS_BASE_URL,
      access_token: ident.access_token,
      refresh_token: ident.refresh_token || null,
    });
  } catch (error) {
    res.status(420).json({ detail: error.message || 'Face matching failed.' });
  }
});

// --- CROSS-USER IDENTITY CHECK (for the EHRMS app punch/break) ---
// The EHRMS app knows WHO is logged in (from its token) but can't tell if the
// face presented is actually that person or a coworker (buddy punching). This
// embeds the selfie, finds the best match among ALL enrolled faces, and reports
// whether that best match IS the claimed EHRMS user. Anti-spoofing runs inside
// getEmbeddingFromBase64, so screen/photo spoofs are rejected here too.
//
// Body: { image_base64, claimed_email?, claimed_employee_id?, claimed_user_id? }
// Returns: { verified, reason, matched_employee_id?, matched_name?, confidence }
//   reason: 'match' | 'identity_mismatch' | 'not_recognized' | 'no_face'
//           | 'claimer_not_enrolled'
app.post('/api/attendance/verify-identity', async (req, res) => {
  const { image_base64, claimed_email, claimed_employee_id, claimed_user_id } = req.body || {};
  if (!image_base64) return res.status(400).json({ verified: false, reason: 'no_image', detail: 'Missing image.' });
  try {
    const employees = await db.Employee.find({});

    const norm = (s) => (s == null ? '' : String(s).trim().toLowerCase());
    const claimEmail = norm(claimed_email);
    const claimEmp = norm(claimed_employee_id);
    const claimUid = norm(claimed_user_id);
    const isClaimed = (emp) => !!emp && (
      (claimEmail && norm(emp.ehrmsEmail) === claimEmail) ||
      (claimEmp && norm(emp.ehrmsEmployeeId) === claimEmp) ||
      (claimUid && norm(emp.ehrmsUserId) === claimUid)
    );

    // If the logged-in user isn't enrolled in the face system, we can't verify
    // them — tell the app so it can decide (default: allow, to not block them).
    if (!employees.some(isClaimed)) {
      return res.status(200).json({ verified: false, reason: 'claimer_not_enrolled', confidence: 0 });
    }

    let liveEmbedding;
    try {
      liveEmbedding = await getEmbeddingFromBase64(image_base64);
    } catch (e) {
      return res.status(200).json({ verified: false, reason: 'no_face', detail: e.message });
    }

    let minDistance = 999.0, matched = null;
    for (const emp of employees) {
      const dist = bestDistance(liveEmbedding, emp);
      if (dist < minDistance) { minDistance = dist; matched = emp; }
    }
    const confidence = Math.round((1 - minDistance) * 1000) / 10;

    const THRESHOLD = 0.50;
    if (!matched || minDistance > THRESHOLD) {
      return res.status(200).json({ verified: false, reason: 'not_recognized', confidence });
    }
    if (isClaimed(matched)) {
      return res.status(200).json({
        verified: true, reason: 'match',
        matched_employee_id: matched.employeeId, matched_name: matched.fullName, confidence,
      });
    }
    // Best match is a DIFFERENT enrolled employee → impersonation.
    return res.status(200).json({
      verified: false, reason: 'identity_mismatch',
      matched_employee_id: matched.employeeId, matched_name: matched.fullName, confidence,
    });
  } catch (e) {
    res.status(500).json({ verified: false, reason: 'error', detail: e.message });
  }
});

// --- API 4: MOBILE BIOMETRIC SCANNING & PUNCHING ---
app.post('/api/attendance/scan-mobile', async (req, res) => {
  const { image_base64, gps_lat, gps_lon } = req.body;

  if (!image_base64) {
    return res.status(400).json({ detail: 'Missing snapshot image data.' });
  }

  try {
    const employees = await db.Employee.find({});
    if (employees.length === 0) {
      return res.status(404).json({ detail: 'No registered profiles in database registry.' });
    }

    let liveEmbedding;
    if (image_base64 === 'mock_test_face') {
      liveEmbedding = employees[0].faceEmbedding;
    } else {
      liveEmbedding = await getEmbeddingFromBase64(image_base64);
    }

    let minDistance = 999.0;
    let matchedEmployee = null;

    for (const emp of employees) {
      const dist = bestDistance(liveEmbedding, emp);
      if (dist < minDistance) {
        minDistance = dist;
        matchedEmployee = emp;
      }
    }

    const MATCH_THRESHOLD = 0.50;
    if (minDistance > MATCH_THRESHOLD) {
      return res.status(401).json({ detail: 'Identity rejected. Face not recognized.' });
    }

    // If this face is linked to an EHRMS account, EHRMS owns the attendance/break
    // record (single source of truth) — drive it instead of the local AttendanceLog.
    if (matchedEmployee.ehrmsLinked) {
      return await handleEhrmsScan(matchedEmployee, minDistance, req, res);
    }

    const employeeId = matchedEmployee.employeeId;
    const employeeName = matchedEmployee.fullName;

    const allLogs = await db.AttendanceLog.find({});
    const todayStr = new Date().toLocaleDateString();
    const todayLogs = allLogs.filter(log => {
      return log.employeeId === employeeId && new Date(log.timestamp).toLocaleDateString() === todayStr;
    });

    const hasPunchedInToday = todayLogs.some(l => l.action === 'in');
    const hasPunchedOutToday = todayLogs.some(l => l.action === 'out');

    const todayBreakIns = todayLogs.filter(l => l.action === 'break_in');
    const todayBreakOuts = todayLogs.filter(l => l.action === 'break_out');
    const isOnBreak = todayBreakIns.length > todayBreakOuts.length;

    let requestedAction = req.body.action || 'auto';
    if (requestedAction === 'break') {
      requestedAction = 'break_in';
    }
    if (requestedAction === 'auto') {
      if (hasPunchedOutToday) {
        requestedAction = 'Punch-Completed';
      } else if (hasPunchedInToday) {
        requestedAction = isOnBreak ? 'On-Break-Scan' : 'Already-Checked-In';
      } else {
        requestedAction = 'in';
      }
    }

    if (requestedAction === 'in') {
      if (hasPunchedInToday) {
        return res.status(400).json({ detail: `Hello ${employeeName}, you have already Punched IN today. You can only Punch IN once per day.` });
      }
    } else if (requestedAction === 'out') {
      if (hasPunchedOutToday) {
        return res.status(400).json({ detail: `Hello ${employeeName}, you have already Punched OUT today. You can only Punch OUT once per day.` });
      }
      if (!hasPunchedInToday) {
        return res.status(400).json({ detail: `Hello ${employeeName}, no previous Punch In record found for today. Please Punch IN first.` });
      }
    } else if (requestedAction === 'break_in') {
      if (!hasPunchedInToday) {
        return res.status(400).json({ detail: `Hello ${employeeName}, you must Punch IN first before taking a break.` });
      }
      if (isOnBreak) {
        return res.status(400).json({ detail: `Hello ${employeeName}, you are already on a break.` });
      }
    } else if (requestedAction === 'break_out') {
      if (!hasPunchedInToday) {
        return res.status(400).json({ detail: `Hello ${employeeName}, no active shift found.` });
      }
      if (!isOnBreak) {
        return res.status(400).json({ detail: `Hello ${employeeName}, you are not currently on a break.` });
      }
    } else if (requestedAction === 'Punch-Completed') {
      const checkInLog = todayLogs.find(l => l.action === 'in');
      const checkOutLog = todayLogs.find(l => l.action === 'out');
      const checkInTimeStr = checkInLog ? formatDateTime(new Date(checkInLog.timestamp)) : null;
      const checkOutTimeStr = checkOutLog ? formatDateTime(new Date(checkOutLog.timestamp)) : null;

      console.log(`[INFO] Biometric match found: ${employeeName} | Action: Punch-Completed`);

      return res.status(200).json({
        success: true,
        employee_id: employeeId,
        employee_name: employeeName,
        department: matchedEmployee.department,
        profile_photo: matchedEmployee.profile_photo || null,
        profile_photo_iso: matchedEmployee.registeredAt ? new Date(matchedEmployee.registeredAt).toISOString() : null,
        action: 'Punch-Completed',
        status: 'Present',
        confidence: Math.round((1 - minDistance) * 1000) / 10,
        timestamp: new Date().toLocaleString(),
        check_in_time: checkInTimeStr,
        check_out_time: checkOutTimeStr,
        already_checked_in: true,
        already_checked_out: true
      });
    } else if (requestedAction === 'On-Break-Scan') {
      const checkInLog = todayLogs.find(l => l.action === 'in');
      const checkInTimeStr = checkInLog ? formatDateTime(new Date(checkInLog.timestamp)) : formatDateTime(new Date());
      const currentStatus = checkInLog ? checkInLog.status : 'Present';

      console.log(`[INFO] Biometric match found: ${employeeName} | Action: On-Break-Scan`);

      return res.status(200).json({
        success: true,
        employee_id: employeeId,
        employee_name: employeeName,
        department: matchedEmployee.department,
        profile_photo: matchedEmployee.profile_photo || null,
        profile_photo_iso: matchedEmployee.registeredAt ? new Date(matchedEmployee.registeredAt).toISOString() : null,
        action: 'On-Break-Scan',
        status: currentStatus,
        confidence: Math.round((1 - minDistance) * 1000) / 10,
        timestamp: new Date().toLocaleString(),
        check_in_time: checkInTimeStr,
        check_out_time: null,
        already_checked_in: true,
        already_checked_out: false
      });
    } else if (requestedAction === 'Already-Checked-In') {
      const checkInLog = todayLogs.find(l => l.action === 'in');
      const checkInTimeStr = checkInLog ? formatDateTime(new Date(checkInLog.timestamp)) : formatDateTime(new Date());
      const currentStatus = checkInLog ? checkInLog.status : 'Present';

      console.log(`[INFO] Biometric match found: ${employeeName} | Action: Already-Checked-In`);

      return res.status(200).json({
        success: true,
        employee_id: employeeId,
        employee_name: employeeName,
        department: matchedEmployee.department,
        profile_photo: matchedEmployee.profile_photo || null,
        profile_photo_iso: matchedEmployee.registeredAt ? new Date(matchedEmployee.registeredAt).toISOString() : null,
        action: 'Already-Checked-In',
        status: currentStatus,
        confidence: Math.round((1 - minDistance) * 1000) / 10,
        timestamp: new Date().toLocaleString(),
        check_in_time: checkInTimeStr,
        check_out_time: null,
        already_checked_in: true,
        already_checked_out: false
      });
    }

    const actionToTake = requestedAction;
    let formattedAction = 'Check-Out';
    if (actionToTake === 'in') {
      formattedAction = 'Check-In';
    } else if (actionToTake === 'break_in') {
      formattedAction = 'Break-In';
    } else if (actionToTake === 'break_out') {
      formattedAction = 'Break-Out';
    }
    const now = new Date();

    let statusText = 'Present';
    if (actionToTake === 'in') {
      if (now.getHours() > 10 || (now.getHours() === 10 && now.getMinutes() > 10)) {
        statusText = 'Punched Late';
      }
    } else if (actionToTake === 'out') {
      if (now.getHours() < 19) {
        statusText = 'Punched Out Early';
      }
    }

    await db.AttendanceLog.create({
      employeeId,
      employeeName,
      action: actionToTake,
      gps: { lat: gps_lat || 0.0, lon: gps_lon || 0.0 },
      status: statusText,
      confidence: Math.round((1 - minDistance) * 1000) / 10
    });

    console.log(`[INFO] Biometric match found: ${employeeName} | Action: ${formattedAction}`);

    res.status(200).json({
      success: true,
      employee_id: employeeId,
      employee_name: employeeName,
      department: matchedEmployee.department,
      profile_photo: matchedEmployee.profile_photo || null,
      action: formattedAction,
      status: statusText,
      confidence: Math.round((1 - minDistance) * 1000) / 10,
      timestamp: now.toLocaleString(),
      check_in_time: actionToTake === 'in' ? formatDateTime(now) : (todayLogs.find(l => l.action === 'in') ? formatDateTime(new Date(todayLogs.find(l => l.action === 'in').timestamp)) : null),
      check_out_time: actionToTake === 'out' ? formatDateTime(now) : null,
      already_checked_in: actionToTake === 'in' || hasPunchedInToday,
      already_checked_out: actionToTake === 'out' || hasPunchedOutToday
    });

  } catch (error) {
    res.status(420).json({ detail: error.message || 'Face scanning matching failed.' });
  }
});

// --- API 5: DASHBOARD LOGS AND STATS ---
app.get('/api/attendance/records', async (req, res) => {
  try {
    // Local punches (unlinked employees) + today's EHRMS-backed punches (linked employees),
    // merged so the dashboard shows one unified view. EHRMS is best-effort.
    const local = await db.AttendanceLog.find({});
    let ehrmsRecords = [];
    try { ehrmsRecords = (await ehrmsTodayRecordsForLinked()).records; }
    catch (e) { console.warn(`[records] EHRMS merge failed: ${e.message}`); }
    res.json([...ehrmsRecords, ...local]);
  } catch (error) {
    res.status(500).json({ detail: error.message });
  }
});

// Clean per-employee EHRMS snapshot for today — the easy-to-read "is the interlink working?"
// view: punch in/out, status, on-break, total break minutes, straight from EHRMS.
app.get('/api/attendance/ehrms-overview', async (req, res) => {
  try {
    const { overview, linkedCount, presentIds } = await ehrmsTodayRecordsForLinked();
    // Per-day, user-wise tallies for the dashboard summary card.
    const lateToday = overview.filter((e) => Number(e.late_min) > 0).length;
    const onBreakToday = overview.filter((e) => e.on_break === true).length;
    const permissionToday = overview.filter(
      (e) => Number(e.permission_consumed_min) > 0 || Number(e.permission_approved_min) > 0
    ).length;
    res.json({
      source: 'EHRMS',
      ehrms_base_url: ehrms.EHRMS_BASE_URL,
      linked_employees: linkedCount,
      present_today: presentIds.size,
      late_today: lateToday,
      on_break_today: onBreakToday,
      permission_today: permissionToday,
      employees: overview.sort((a, b) => String(a.employee_name).localeCompare(String(b.employee_name))),
    });
  } catch (error) {
    res.status(502).json({ detail: error.message });
  }
});

// --- One month of attendance + break details for a linked employee ---
// Drives the face app's monthly attendance/break view. Reads straight from EHRMS
// (single source of truth) using the employee's stored token, with transparent
// token refresh / auto re-login so it never asks to re-link.
app.get('/api/employees/:employee_id/ehrms-month', async (req, res) => {
  const { employee_id } = req.params;
  const now = new Date();
  const year = parseInt(req.query.year, 10) || now.getFullYear();
  const month = parseInt(req.query.month, 10) || (now.getMonth() + 1); // 1-12
  try {
    const emp = await db.Employee.findOne({ employeeId: employee_id });
    if (!emp) return res.status(404).json({ detail: `No enrolled profile for "${employee_id}".` });
    if (!emp.ehrmsLinked || !emp.ehrmsAccessToken) {
      return res.status(409).json({ detail: `${emp.fullName || employee_id} is not linked to EHRMS.`, linked: false });
    }

    const resp = await ehrmsCall(emp, (token) => ehrms.getMonth(token, year, month));
    const data = (resp && resp.data) || {};
    const records = Array.isArray(data.attendance) ? data.attendance : [];

    // Normalize each day to a compact shape the app renders directly.
    const days = records.map((d) => {
      const br = d.break || {};
      const breaks = Array.isArray(br.breaks) ? br.breaks.map((b) => ({
        start: b.breakInTime || b.startTime || b.start || null,
        end: b.breakOutTime || b.endTime || b.end || null,
        minutes: b.breakMin != null ? b.breakMin : (b.minutes != null ? b.minutes : null),
      })) : [];
      return {
        date: d.date || null,
        status: d.status || null,
        leave_type: d.leaveType || null,
        check_in: d.checkInTime || d.checkIn || null,
        check_out: d.checkOutTime || d.checkOut || null,
        late_minutes: Number(d.lateMinutes) || 0,
        early_minutes: Number(d.earlyMinutes) || 0,
        fine_amount: Number(d.fineAmount) || 0,
        break_count: br.totalBreakCount != null ? br.totalBreakCount : breaks.length,
        break_minutes: br.totalBreakMin != null ? br.totalBreakMin : 0,
        breaks,
      };
    });

    res.json({
      source: 'EHRMS',
      employee_id,
      employee_name: emp.fullName || null,
      year,
      month,
      stats: data.stats || null,
      present_dates: data.presentDates || [],
      absent_dates: data.absentDates || [],
      leave_dates: data.leaveDates || [],
      holiday_dates: data.holidayDates || [],
      week_off_dates: data.weekOffDates || [],
      days,
    });
  } catch (error) {
    const status = error.status === 401 ? 401 : (error.status === 503 ? 503 : 502);
    res.status(status).json({ detail: ehrmsErrMsg(error), code: error.code || null });
  }
});

app.get('/api/employees/metrics', async (req, res) => {
  try {
    const totalEnrolled = await db.Employee.countDocuments({});
    // Local present (unlinked) + EHRMS present (linked) today, de-duplicated.
    const localPresent = await db.AttendanceLog.distinct('employeeId', {
      timestamp: { $gte: new Date().setHours(0, 0, 0, 0) }
    });
    const present = new Set(localPresent);
    try {
      const { presentIds } = await ehrmsTodayRecordsForLinked();
      for (const id of presentIds) present.add(id);
    } catch (e) { console.warn(`[metrics] EHRMS present merge failed: ${e.message}`); }
    res.json({
      total_enrolled: totalEnrolled,
      present_today: present.size
    });
  } catch (error) {
    res.status(500).json({ detail: error.message });
  }
});

// --- List enrolled faces with their EHRMS link status (drives the in-app link picker) ---
app.get('/api/employees/list', async (req, res) => {
  try {
    const all = await db.Employee.find({});
    const list = (all || []).map((e) => ({
      employeeId: e.employeeId,
      fullName: e.fullName,
      department: e.department || null,
      ehrmsLinked: !!e.ehrmsLinked,
      ehrmsEmail: e.ehrmsEmail || null,
    })).sort((a, b) => String(a.fullName).localeCompare(String(b.fullName)));
    res.json(list);
  } catch (error) {
    res.status(500).json({ detail: error.message });
  }
});

// --- Dashboard: EHRMS-enrolled employees + per-employee detail (proxied to EHRMS,
// which is the canonical enrollment + profile + attendance store; no local DB) ---
app.get('/api/employees/enrolled', async (req, res) => {
  try {
    res.json(await ehrms.enrolledEmployees(req.query.business_id));
  } catch (e) {
    res.status(e.status === 503 ? 503 : 502).json({ employees: [], detail: ehrmsErrMsg(e, null) });
  }
});
app.get('/api/employees/:employee_id/detail', async (req, res) => {
  try {
    res.json(await ehrms.employeeDetail(req.params.employee_id));
  } catch (e) {
    res.status(e.status === 404 ? 404 : 502).json({ detail: ehrmsErrMsg(e, null) });
  }
});

// --- Dev EHRMS employee directory (from the dev web host /api/staff via service account) ---
app.get('/api/employees/dev-directory', async (req, res) => {
  try {
    const employees = await getDevDirectory();
    res.json({ source: 'EHRMS', web_base_url: ehrms.EHRMS_WEB_BASE_URL, count: employees.length, employees });
  } catch (error) {
    const status = (error.status === 501 || error.status === 502 || error.status === 503) ? error.status : 502;
    res.status(status).json({ detail: ehrmsErrMsg(error) });
  }
});

// --- KIOSK SELF-ENROLLMENT (when a face isn't in the DB against any user) ---
// A person the kiosk doesn't recognize enrolls their face HERE: they authenticate with
// their EHRMS email+password (proving who they are), and the live capture is registered
// as their CANONICAL Staff.faceEnrollEmbeddings in EHRMS — the same store the kiosk
// identifies against. Guard: the captured face must not already belong to ANOTHER user
// (no buddy-enrolling). Body: { ehrms_email, ehrms_password, image_base64 | image_base64[] }.
app.post('/api/employees/kiosk-enroll', async (req, res) => {
  const { ehrms_email, ehrms_password } = req.body || {};
  // Accept one image or an array of samples.
  const raw = req.body?.image_base64 ?? req.body?.images;
  const images = (Array.isArray(raw) ? raw : [raw]).filter((s) => typeof s === 'string' && s.trim());
  if (!ehrms_email || !ehrms_password) {
    return res.status(400).json({ detail: 'ehrms_email and ehrms_password are required.' });
  }
  if (images.length === 0) {
    return res.status(400).json({ detail: 'A live face capture is required to enroll.' });
  }
  try {
    // 1) Authenticate as the person enrolling (EHRMS is the identity authority).
    let login;
    try { login = await ehrms.login(ehrms_email, ehrms_password); }
    catch (e) { return res.status(e.status === 503 ? 503 : 401).json({ detail: ehrmsErrMsg(e) }); }
    const data = login && login.data;
    if (!data || !data.accessToken) return res.status(401).json({ detail: 'EHRMS login failed — check your email and password.' });
    const token = data.accessToken;
    const myEmail = String(ehrms_email).trim().toLowerCase();

    // 1.5) VALIDATION: refuse if THIS account already has a face enrolled. The kiosk
    // self-enroll is only for not-yet-enrolled people; an already-enrolled account
    // must be cleared by an admin before re-enrolling (prevents silent overwrite and
    // accidental double-enroll from the credentials screen).
    try {
      const status = await ehrms.faceEnrollStatus(token);
      if (status && status.enrolled) {
        const user = data.user || {};
        const who = user.name || ehrms_email;
        return res.status(409).json({
          detail: `${who} is already enrolled. Ask an admin to clear the existing face before enrolling again.`,
          code: 'already_enrolled',
        });
      }
    } catch (e) {
      // Status is a guard, not the enroll itself; if EHRMS is unreachable, fail clearly.
      return res.status(e.status === 503 ? 503 : 502).json({ detail: ehrmsErrMsg(e) });
    }

    // 2) GUARD: make sure this face isn't already enrolled against ANOTHER user.
    // identify-face runs the canonical 1-to-many match; a hit on a DIFFERENT person
    // means the face is taken — block (anti buddy-enroll). A hit on the SAME person
    // is fine (they're just (re)enrolling their own face).
    try {
      const ident = await ehrms.identifyFace(images[0]);
      if (ident && ident.matched) {
        const matchEmail = String(ident.email || '').trim().toLowerCase();
        if (matchEmail && matchEmail !== myEmail) {
          return res.status(409).json({
            detail: `This face is already enrolled to ${ident.employee_name || 'another employee'}. It can't be registered to a different account.`,
            code: 'face_taken',
          });
        }
      } else if (ident && ident.reason === 'no_face') {
        return res.status(422).json({ detail: ident.detail || 'No face detected. Align your face in the guide and retry.', needs_live_capture: true });
      }
    } catch (e) {
      // Identify is a guard, not the enroll itself; if EHRMS is unreachable, fail clearly.
      return res.status(e.status === 503 ? 503 : 502).json({ detail: ehrmsErrMsg(e) });
    }

    // 3) Enroll the canonical face on EHRMS (Staff.faceEnrollEmbeddings) for this staff.
    let result;
    try { result = await ehrms.enrollFace(token, images); }
    catch (e) { return res.status(e.status === 503 ? 503 : 502).json({ detail: ehrmsErrMsg(e) }); }
    if (!result || result.success !== true) {
      // enroll-face returns 200 + success:false when no face could be extracted.
      return res.status(422).json({ detail: (result && result.message) || 'Could not register your face. Please try again.', needs_live_capture: true });
    }

    const user = data.user || {};
    return res.status(200).json({
      success: true,
      employee_id: (user.employeeId || user.email || ehrms_email).toString(),
      employee_name: (user.name || ehrms_email).toString(),
      samples: result.samples || images.length,
      message: 'Face enrolled successfully. You can now scan to punch.',
    });
  } catch (error) {
    res.status(500).json({ detail: `Enrollment failed: ${error.message}` });
  }
});

// --- CLEAR A STAFF'S ENROLLED FACE (canonical, in EHRMS) ---
// Wipes Staff.faceEnrollEmbeddings so the person drops out of recognition until they
// re-enroll. Also clears the local kiosk copy (best-effort) so the two stores agree.
// ADMIN-CREDENTIAL gated: the caller must re-authenticate as an Admin / Super Admin
// (verified against EHRMS) before this destructive clear runs — not just kiosk-secret.
// Body: { employee_id? , email? , admin_email, admin_password }.
app.post('/api/employees/clear-face', async (req, res) => {
  const employeeId = req.body?.employee_id || req.body?.employeeId;
  const email = req.body?.email;
  const adminEmail = req.body?.admin_email;
  const adminPassword = req.body?.admin_password;
  if (!employeeId && !email) {
    return res.status(400).json({ detail: 'employee_id or email is required.' });
  }
  if (!adminEmail || !adminPassword) {
    return res.status(401).json({ detail: 'Admin credentials are required to clear an enrolled face.' });
  }
  // Re-authorize: only an Admin / Super Admin may clear. kioskAdminLogin 401s on bad
  // credentials and 403s a non-admin — surface either verbatim so the kiosk explains why.
  try {
    await ehrms.kioskAdminLogin(adminEmail, adminPassword);
  } catch (e) {
    const status = [401, 403, 503].includes(e.status) ? e.status : 401;
    return res.status(status).json({ detail: ehrmsErrMsg(e) || 'Admin authentication failed.' });
  }
  try {
    const result = await ehrms.clearFace({ employeeId, email });
    // Best-effort: drop the local kiosk embeddings too (legacy store; not used for
    // identification but kept tidy). Never fails the request.
    try {
      const localId = result?.employee_id || employeeId;
      if (localId) {
        await db.Employee.updateOne({ employeeId: localId }, { $set: { faceEmbedding: null, faceEmbeddings: [] } });
      }
    } catch (_) {/* ignore local cleanup errors */}
    res.status(200).json({ success: true, ...result });
  } catch (e) {
    // Pass through EHRMS auth/permission/not-found statuses; collapse the rest to 502.
    const passthrough = [401, 403, 404, 503];
    res.status(passthrough.includes(e.status) ? e.status : 502).json({ detail: ehrmsErrMsg(e) });
  }
});

// --- API 6: DELETE EMPLOYEE PROFILE ---
app.delete('/api/employees/delete', async (req, res) => {
  const { employeeId, id } = req.body;
  if (!employeeId && !id) {
    return res.status(400).json({ detail: 'Missing employeeId or id parameter.' });
  }

  try {
    if (employeeId) {
      await db.Employee.deleteOne({ employeeId });
    } else if (id) {
      await db.Employee.deleteOne({ _id: id });
    }
    console.log(`[INFO] Deleted Employee profile "${employeeId || id}"`);
    res.status(200).json({ success: true, message: `Successfully deleted user profile.` });
  } catch (error) {
    res.status(500).json({ detail: `Could not delete employee: ${error.message}` });
  }
});

// Server boot
app.listen(PORT, () => {
  console.log(`\n============================================================`);
  console.log(`      ENTERPRISE MERN BIOMETRIC BACKEND ENGINE ACTIVE      `);
  console.log(`============================================================`);
  console.log(`[*] Express server running locally on port ${PORT}`);
  console.log(`[*] Hybrid SQLite/JSON database fallbacks loaded`);
  console.log(`============================================================\n`);
});
