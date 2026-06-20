# ============================================================
#  FaceAttend - One-click launcher
#  Starts: MongoDB -> Node/MongoDB backend (8000) -> Frontend (5173)
#  Usage:  right-click > Run with PowerShell,  OR  in a terminal:
#          powershell -ExecutionPolicy Bypass -File .\start-all.ps1
# ============================================================

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Write-Host "`n=== FaceAttend launcher ===`n" -ForegroundColor Cyan

# --- 1. MongoDB ---
$mongo = Get-Service MongoDB -ErrorAction SilentlyContinue
if ($null -eq $mongo) {
    Write-Host "[!] MongoDB service not found. Install MongoDB 7.0 first." -ForegroundColor Red
    exit 1
}
if ($mongo.Status -ne 'Running') {
    Write-Host "[*] Starting MongoDB service (needs admin)..." -ForegroundColor Yellow
    Start-Process -FilePath "net" -ArgumentList "start MongoDB" -Verb RunAs -Wait
} else {
    Write-Host "[ok] MongoDB already running" -ForegroundColor Green
}

# --- 2. Backend (Node + MongoDB) on port 8000 ---
$backend = Join-Path $root "backend-node"
if (-not (Test-Path (Join-Path $backend "node_modules"))) {
    Write-Host "[*] Installing backend dependencies..." -ForegroundColor Yellow
    Push-Location $backend; npm install; Pop-Location
}
Write-Host "[*] Launching backend on http://localhost:8000 ..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$backend'; npm start"

# --- 3. Frontend (Vite) on port 5173 ---
$frontend = Join-Path $root "frontend"
if (-not (Test-Path (Join-Path $frontend "node_modules"))) {
    Write-Host "[*] Installing frontend dependencies..." -ForegroundColor Yellow
    Push-Location $frontend; npm install; Pop-Location
}
Write-Host "[*] Launching frontend on http://localhost:5173 ..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$frontend'; npm run dev"

Write-Host "`n=== All services launching in separate windows ===" -ForegroundColor Cyan
Write-Host "  Backend : http://localhost:8000/api/health"
Write-Host "  Frontend: http://localhost:5173"
Write-Host "  Mobile  : Flutter app -> http://192.168.0.28:8000/api`n"
