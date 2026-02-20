#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace/code-generation/dvedice_kavia_vijay-45-861/vDeviceControlPlane(Backend)"
mkdir -p "${WS}" && cd "${WS}"
VENV_PY="${WS}/.venv/bin/python"
if [ ! -x "${VENV_PY}" ]; then echo "venv python missing, run install step" >&2; exit 4; fi
# app layout - valid FastAPI code
mkdir -p "${WS}/app"
cat > "${WS}/app/main.py" <<'PY'
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def read_root():
    return {"status": "ok"}
PY
# start script: robust activation, redirect logs, trap signals
cat > "${WS}/start.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
WS="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$WS/.uvicorn.pid"
OUTLOG="$WS/uvicorn.out"
ERRLOG="$WS/uvicorn.err"
PORT_VAL="${PORT:-8000}"
# try to source VDEVICE_VENV if present and activation exists
if [ -n "${VDEVICE_VENV:-}" ] && [ -f "${VDEVICE_VENV}/bin/activate" ]; then
  # shellcheck source=/dev/null
  . "${VDEVICE_VENV}/bin/activate"
elif [ -f "${WS}/.venv/bin/activate" ]; then
  # shellcheck source=/dev/null
  . "${WS}/.venv/bin/activate"
fi
# resolve uvicorn command: prefer venv python -m uvicorn to avoid PATH issues
if [ -x "${WS}/.venv/bin/python" ]; then
  UV_CMD=("${WS}/.venv/bin/python" -m uvicorn app.main:app --host 0.0.0.0 --port "${PORT_VAL}")
else
  UV_CMD=(uvicorn app.main:app --host 0.0.0.0 --port "${PORT_VAL}")
fi
# start server in foreground, redirect output, write pidfile
"${UV_CMD[@]}" >"${OUTLOG}" 2>"${ERRLOG}" &
UV_PID=$!
echo "$UV_PID" > "$PIDFILE"
# trap signals and forward to uvicorn
trap 'kill -TERM "$UV_PID" 2>/dev/null || true; wait "$UV_PID"' TERM INT
wait "$UV_PID"
SH
chmod +x "${WS}/start.sh"
