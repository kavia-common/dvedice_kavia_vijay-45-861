#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace/code-generation/dvedice_kavia_vijay-45-861/vDeviceControlPlane(Backend)"
SQLITE_PATH="${WS}/vdevice_dev.db"
REQ_FILE="${WS}/requirements.txt"
TMP_ENV="/tmp/vdevice_env.sh"
PROFILE_DEST="/etc/profile.d/vdevice_env.sh"
# ensure workspace exists and is owned by current user
sudo mkdir -p "${WS}" && sudo chown "$(id -u):$(id -g)" "${WS}"
# python version check
if ! command -v python3 >/dev/null 2>&1; then echo "python3 not found" >&2; exit 2; fi
PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PYVER" | cut -d. -f1)
PY_MINOR=$(echo "$PYVER" | cut -d. -f2)
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]; }; then
  echo "python3 >= 3.10 required (found $PYVER)" >&2; exit 3
fi
# create venv idempotently
if [ ! -d "${WS}/.venv" ]; then python3 -m venv "${WS}/.venv"; fi
VENV_PY="${WS}/.venv/bin/python"
if [ ! -x "${VENV_PY}" ]; then echo "venv python missing after venv creation" >&2; exit 4; fi
# ensure pip exists in venv and upgrade packaging tools
if ! "${VENV_PY}" -m pip --version >/dev/null 2>&1; then
  "${VENV_PY}" -m ensurepip --upgrade >/dev/null 2>&1 || true
fi
"${VENV_PY}" -m pip install --upgrade --quiet pip setuptools wheel
# ensure sqlite file exists
mkdir -p "${WS}"
touch "${SQLITE_PATH}"
chmod 644 "${SQLITE_PATH}"
# write requirements (minimal)
cat > "${REQ_FILE}" <<'EOF'
# minimal runtime requirements (loose pins by choice for dev)
fastapi
uvicorn[standard]
EOF
# install runtime + test deps into venv (quiet)
"${VENV_PY}" -m pip install --upgrade --quiet -r "${REQ_FILE}" pytest httpx requests
# log installed package versions (best-effort)
"${VENV_PY}" -m pip show fastapi uvicorn pytest httpx requests || true
# write /etc/profile.d pointer atomically, back up existing if present
if [ -f "${PROFILE_DEST}" ]; then sudo cp -a "${PROFILE_DEST}" "${PROFILE_DEST}.bak" || true; fi
cat > "${TMP_ENV}" <<EOF
# vDeviceControlPlane project environment pointer
export VDEVICE_VENV="${WS}/.venv"
export APP_ENV=development
export PORT=8000
# Use sqlite file inside workspace; form sqlite:///<absolute-path>
export DATABASE_URL="sqlite:///${SQLITE_PATH}"
EOF
sudo mv "${TMP_ENV}" "${PROFILE_DEST}" && sudo chmod 644 "${PROFILE_DEST}"
# final validation of imports using venv python
"${VENV_PY}" - <<'PY'
import sys
try:
    import fastapi, uvicorn, pytest, httpx, requests
except Exception as e:
    print('dependency import failed:', e, file=sys.stderr)
    sys.exit(6)
print('deps ok')
PY
