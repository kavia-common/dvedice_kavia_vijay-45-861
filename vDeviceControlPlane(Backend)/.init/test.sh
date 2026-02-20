#!/usr/bin/env bash
set -euo pipefail

WS="/home/kavia/workspace/code-generation/dvedice_kavia_vijay-45-861/vDeviceControlPlane(Backend)"
VENV_PY="${WS}/.venv/bin/python"

if [ ! -x "${VENV_PY}" ]; then
  echo "venv python missing: ${VENV_PY}" >&2
  exit 5
fi

cd "${WS}"
mkdir -p "${WS}/tests"
cat > "${WS}/tests/test_root.py" <<'PY'
from fastapi.testclient import TestClient
from app.main import app
client = TestClient(app)

def test_root():
    r = client.get('/')
    assert r.status_code == 200
    assert r.json().get('status') == 'ok'
PY

# quick import check before running pytest
"${VENV_PY}" - <<'PY'
import sys
try:
    from fastapi.testclient import TestClient
    from app.main import app
except Exception as e:
    print('test imports failed:', e, file=sys.stderr)
    sys.exit(7)
print('test imports ok')
PY

# run pytest via venv python
"${VENV_PY}" -m pytest -q || { echo "pytest failed" >&2; exit 3; }
