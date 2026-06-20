#!/usr/bin/env bash
# One-command deploy for the face-attendance backend (run ON the server, repo root):
#   bash deploy.sh
# Override the pm2 app name if it differs:  PM2_APP=face-at bash deploy.sh
#
# Pulls the latest code, installs deps ONLY when they changed (or on first run),
# then gracefully reloads pm2 (re-reads .env, respawns the face AI worker).
#
# NOTE: the face backend reaches EHRMS for identification + the punch token, so make
# sure the EHRMS server is deployed FIRST (it must mint the token this app uses).
set -euo pipefail
cd "$(dirname "$0")"

PM2_APP="${PM2_APP:-face-at}"
echo "[deploy] repo: $(pwd)  | pm2 app: $PM2_APP"

OLD=$(git rev-parse HEAD)
git pull --ff-only
NEW=$(git rev-parse HEAD)
CHANGED=$(git diff --name-only "$OLD" "$NEW" || true)
[ "$OLD" = "$NEW" ] && echo "[deploy] code already up to date ($NEW)" || echo "[deploy] $OLD -> $NEW"

# Node deps — only if package.json/lock changed.
if echo "$CHANGED" | grep -q 'backend-node/package'; then
  echo "[deploy] backend Node deps changed -> npm ci"
  (cd backend-node && npm ci --omit=dev)
fi

# Python AI worker — install on FIRST run (no venv) or when requirements change.
if [ ! -x backend/venv/bin/python ]; then
  echo "[deploy] face engine venv missing -> first-time install"
  sudo apt-get update && sudo apt-get install -y build-essential cmake python3-dev python3-venv
  (cd backend && python3 -m venv venv && ./venv/bin/pip install -U pip && ./venv/bin/pip install -r requirements.txt)
elif echo "$CHANGED" | grep -q 'backend/requirements.txt'; then
  echo "[deploy] face engine requirements changed -> reinstall"
  (cd backend && ./venv/bin/pip install -r requirements.txt)
fi

echo "[deploy] reloading pm2 (graceful, re-reads .env)"
pm2 reload "$PM2_APP" --update-env || pm2 restart "$PM2_APP" --update-env
echo "[deploy] done ✓  ($NEW)"
