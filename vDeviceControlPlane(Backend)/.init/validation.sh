#!/usr/bin/env bash
set -euo pipefail
# Validation script: start app via start.sh (background), wait for pidfile, poll root endpoint until JSON {"status":"ok"}, then stop server and ensure clean shutdown.
WS="/home/kavia/workspace/code-generation/dvedice_kavia_vijay-45-861/vDeviceControlPlane(Backend)"
cd "${WS}"
VENV_PY="${WS}/.venv/bin/python"
if [ ! -x "${VENV_PY}" ]; then echo "venv python missing" >&2; exit 5; fi
if [ ! -x "${WS}/start.sh" ]; then echo "start.sh missing" >&2; exit 6; fi
PORT_VAL=${PORT:-8000}
LOG_OUT="$WS/uvicorn.out"
LOG_ERR="$WS/uvicorn.err"
PIDFILE="$WS/.uvicorn.pid"
# start the start.sh in background (it writes the pidfile itself)
"${WS}/start.sh" &
START_SH_PID=$!
# wait for pidfile up to ~20s
RETRIES=40
SLEEP=0.5
i=0
while [ $i -lt $RETRIES ]; do
  if [ -s "$PIDFILE" ]; then break; fi
  if ! kill -0 "$START_SH_PID" 2>/dev/null; then
    echo "start.sh terminated before pidfile created" >&2
    echo "--- uvicorn.out ---" >&2; [ -f "$LOG_OUT" ] && tail -n 200 "$LOG_OUT" >&2 || true
    echo "--- uvicorn.err ---" >&2; [ -f "$LOG_ERR" ] && tail -n 200 "$LOG_ERR" >&2 || true
    exit 7
  fi
  sleep $SLEEP
  i=$((i+1))
done
if [ ! -s "$PIDFILE" ]; then echo "pidfile not found" >&2; kill -TERM "$START_SH_PID" 2>/dev/null || true; exit 8; fi
UV_PID=$(cat "$PIDFILE")
# poll endpoint and validate JSON using small python validator
RESP_FILE="/tmp/vdevice_validation_resp.json"
PY_VALIDATOR="/tmp/vdevice_validate.py"
cat > "$PY_VALIDATOR" <<'PY'
import sys, json
p=sys.argv[1]
try:
    data=json.load(open(p))
    if data.get('status')=='ok':
        sys.exit(0)
except Exception:
    pass
sys.exit(2)
PY
attempt=0
max=40
sleep_time=0.25
while [ $attempt -lt $max ]; do
  sleep $sleep_time
  if curl -sS --fail "http://127.0.0.1:${PORT_VAL}/" -o "$RESP_FILE" 2>/dev/null; then
    if "${VENV_PY}" "$PY_VALIDATOR" "$RESP_FILE"; then
      break
    fi
  fi
  attempt=$((attempt+1))
  # simple incremental backoff (cap at 2s)
  sleep_time=$(awk "BEGIN{t=$sleep_time*1.3; if(t>2) t=2; printf \"%f\", t}")
done
rm -f "$PY_VALIDATOR" || true
if [ $attempt -ge $max ]; then echo "server did not respond correctly" >&2; [ -f "$RESP_FILE" ] && cat "$RESP_FILE" >&2; kill -TERM "$UV_PID" 2>/dev/null || true; kill -TERM "$START_SH_PID" 2>/dev/null || true; exit 9; fi
# stop server gracefully
kill -TERM "$UV_PID" 2>/dev/null || true
# wait for uvicorn to exit up to 10s
wait_pid_timeout=10
t=0
while kill -0 "$UV_PID" 2>/dev/null && [ $t -lt $wait_pid_timeout ]; do
  sleep 0.5
  t=$((t+1))
done
if kill -0 "$UV_PID" 2>/dev/null; then
  kill -KILL "$UV_PID" 2>/dev/null || true
fi
# also ensure start.sh is not running
kill -0 "$START_SH_PID" 2>/dev/null && kill -TERM "$START_SH_PID" 2>/dev/null || true
rm -f "$PIDFILE" "$RESP_FILE" || true
echo "validation ok"
