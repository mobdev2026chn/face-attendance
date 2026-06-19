const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

// Resolve a usable Python interpreter across OSes. Order:
//   1. PYTHON_BIN from .env — but only if it actually exists on disk, so a stale
//      Windows path copied to a Linux server (or vice-versa) is skipped, not fatal.
//   2. The project venv, with the platform-correct layout (bin/python on POSIX,
//      Scripts\python.exe on Windows).
//   3. python3 / python on PATH as a last resort.
// On Windows, bare "python" often resolves to the Microsoft Store alias stub
// (exit code 9009), so the explicit venv path is preferred there.
function resolvePythonBin() {
  const candidates = [];
  if (process.env.PYTHON_BIN) candidates.push(process.env.PYTHON_BIN);
  const venv = path.join(__dirname, '..', 'backend', 'venv');
  candidates.push(
    process.platform === 'win32'
      ? path.join(venv, 'Scripts', 'python.exe')
      : path.join(venv, 'bin', 'python'),
  );
  for (const c of candidates) {
    try {
      if (fs.existsSync(c)) return c;
    } catch (_) {
      /* ignore and try the next candidate */
    }
  }
  return process.platform === 'win32' ? 'python' : 'python3';
}

let pyProcess = null;
let currentResolve = null;
let currentReject = null;
let stdoutBuffer = '';
const queue = [];
let processing = false;

function initPyProcess() {
  const scriptPath = path.join(__dirname, 'extract_face_worker.py');
  // Override with PYTHON_BIN in .env if your interpreter lives elsewhere.
  const pythonBin = resolvePythonBin();
  console.log(`[INFO] Spawning persistent Python AI Engine Worker using: ${pythonBin}`);
  // Cap BLAS/OpenMP thread pools to 1. numpy's bundled OpenBLAS otherwise tries to
  // allocate per-core buffers and crashes ("Memory allocation still failed after 10
  // retries") under memory pressure, taking the worker down on import.
  pyProcess = spawn(pythonBin, [scriptPath], {
    env: {
      ...process.env,
      OPENBLAS_NUM_THREADS: '1',
      OMP_NUM_THREADS: '1',
      MKL_NUM_THREADS: '1',
      PYTHONIOENCODING: 'utf-8',
    },
  });
  
  pyProcess.stdout.on('data', (data) => {
    stdoutBuffer += data.toString();
    if (stdoutBuffer.includes('\n')) {
      const parts = stdoutBuffer.split('\n');
      // The first element is the complete response
      const completeLine = parts[0];
      stdoutBuffer = parts.slice(1).join('\n');
      
      if (currentResolve) {
        try {
          const parsed = JSON.parse(completeLine.trim());
          if (parsed.error) {
            currentReject(new Error(parsed.error));
          } else {
            currentResolve(parsed.embedding);
          }
        } catch (err) {
          currentReject(new Error(`Failed to parse Python stdout: ${completeLine}. Error: ${err.message}`));
        }
        currentResolve = null;
        currentReject = null;
      }
    }
  });

  pyProcess.stderr.on('data', (data) => {
    console.error(`[AI ENGINE WORKER ERROR] ${data.toString().trim()}`);
  });

  pyProcess.on('error', (err) => {
    // e.g. ENOENT when the interpreter path is wrong. Without this listener Node
    // re-throws the error and takes the whole backend down.
    console.error(`[ERROR] Failed to spawn Python AI Engine Worker (${pythonBin}): ${err.message}`);
    pyProcess = null;
    if (currentReject) {
      currentReject(err);
      currentResolve = null;
      currentReject = null;
    }
    processing = false;
  });

  pyProcess.on('close', (code) => {
    console.warn(`[WARNING] Python AI Engine Worker closed with code ${code}. Restarting on next request.`);
    pyProcess = null;
    currentResolve = null;
    currentReject = null;
    stdoutBuffer = '';
    processing = false;
  });
}

// Warm up the process immediately on boot!
initPyProcess();

/**
 * Invokes the persistent python face recognition worker to extract the 128D descriptor array
 * @param {string} base64Str - The captured camera frame base64 string
 * @returns {Promise<Array<number>>} - Resolves to the 128-dimensional face embedding array
 */
function getEmbeddingFromBase64(base64Str) {
  return new Promise((resolve, reject) => {
    const payload = base64Str.replace(/[\r\n]/g, '');
    queue.push({ payload, resolve, reject });
    processQueue();
  });
}

/**
 * Lenient enrollment from a STORED photo (EHRMS avatar / punch selfie): skips the
 * kiosk guards and retries rotations (handles upside-down selfies). Returns the 128D vector.
 */
function getEnrollEmbeddingFromBase64(base64Str) {
  return new Promise((resolve, reject) => {
    const clean = base64Str.replace(/[\r\n]/g, '');
    const payload = JSON.stringify({ mode: 'enroll', image: clean });
    queue.push({ payload, resolve, reject });
    processQueue();
  });
}

async function processQueue() {
  if (processing || queue.length === 0) return;
  processing = true;

  const { payload, resolve, reject } = queue.shift();

  try {
    if (!pyProcess) {
      initPyProcess();
      // Give a tiny moment for process to boot if it had died
      await new Promise(r => setTimeout(r, 200));
    }

    currentResolve = resolve;
    currentReject = reject;

    // payload is already a single line (raw base64 for scan, or compact JSON for enroll).
    pyProcess.stdin.write(payload + '\n');

    // Polling safety loop to clear the worker processing lock when resolved/rejected
    const checkDone = setInterval(() => {
      if (currentResolve === null) {
        clearInterval(checkDone);
        processing = false;
        processQueue();
      }
    }, 5);

  } catch (err) {
    reject(new Error(`AI Engine worker execution crash: ${err.message}`));
    processing = false;
    processQueue();
  }
}

/**
 * Calculates Euclidean distance between two 128D face vectors
 * @param {Array<number>} vecA 
 * @param {Array<number>} vecB 
 * @returns {number}
 */
function calculateDistance(vecA, vecB) {
  if (vecA.length !== vecB.length) return 999.0;
  let sum = 0;
  for (let i = 0; i < vecA.length; i++) {
    sum += Math.pow(vecA[i] - vecB[i], 2);
  }
  return Math.sqrt(sum);
}

module.exports = { getEmbeddingFromBase64, getEnrollEmbeddingFromBase64, calculateDistance };
