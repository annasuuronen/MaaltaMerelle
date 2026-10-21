#!/usr/bin/env bash
# Existing entry point; host-Python supervisor runs offline tests once.
set -Eeuo pipefail
umask 077
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# Preserve this before loading r-env/461. No installers, retries or CSC connections.
MM_PYTHON="${MM_HOST_PYTHON:-$(command -v python3 || true)}"
if [[ "$MM_PYTHON" != /* || ! -x "$MM_PYTHON" ]]; then
  echo '========== TULOKSET ALKAVAT =========='
  echo 'RESULT=FAIL REASON=HOST_PYTHON_MISSING PASS=0 FAIL=0 NOT_RUN=4'
  exit 1
fi
exec "$MM_PYTHON" -B "$HERE/run_one_shot.py" "$@"
