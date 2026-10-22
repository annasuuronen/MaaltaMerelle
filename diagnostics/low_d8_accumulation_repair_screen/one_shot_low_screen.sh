#!/usr/bin/env bash
# Single bounded LOW screening. No Slurm, Whitebox, D8 rebuild, accumulation.
set -Eeuo pipefail
umask 077
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd -- "$HERE/../.." && pwd -P)"
if [[ ! "${MM_EXPECTED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'STOP: EXPECTED_FULL_COMMIT_REQUIRED' >&2; exit 1
fi
if [[ "$(git -C "$REPO" rev-parse HEAD)" != "$MM_EXPECTED_COMMIT" ||
      "$(git -C "$REPO" branch --show-current)" != "codex/low-d8-accumulation-repair-screen-v1" ||
      "$(git -C "$REPO" remote get-url origin)" != "https://github.com/annasuuronen/MaaltaMerelle.git" ||
      -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo 'STOP: WRONG_BRANCH_OR_COMMIT_OR_DIRTY' >&2; exit 1
fi
if ! command -v timeout >/dev/null || ! command -v python3 >/dev/null; then
  echo 'STOP: PYTHON_OR_TIMEOUT_MISSING' >&2; exit 1
fi
if ! command -v Rscript >/dev/null; then
  if command -v module >/dev/null 2>&1; then module load r-env/461
  else echo 'STOP: RSCRIPT_MISSING' >&2; exit 1; fi
fi
export PYTHONDONTWRITEBYTECODE=1
W="$(mktemp -d /scratch/project_2004707/pienvedet/mm_low_d8_screen.XXXXXXXX)"
echo "SCREEN_WORK=$W"
timeout 15s python3 "$HERE/audit.py" selftest > "$W/selftest.log" 2>&1 || {
  cat "$W/selftest.log" >&2; echo 'STOP: SELFTEST_FAILED' >&2; exit 1; }
timeout 15s python3 "$HERE/audit.py" make --centers "$W/centers.csv" --cells "$W/cells.csv"
timeout 240s Rscript --vanilla "$HERE/read_low_samples.R" "$W/cells.csv" "$W/raw.csv" > "$W/raster_read.log" 2>&1 || {
  cat "$W/raster_read.log" >&2; echo 'STOP: BOUNDED_RASTER_READ_FAILED' >&2; exit 1; }
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo 'STOP: REPO_MODIFIED' >&2; exit 1
fi
echo "SELFTEST=PASS"
cat "$W/raster_read.log"
timeout 20s python3 "$HERE/audit.py" analyse --centers "$W/centers.csv" --raw "$W/raw.csv" | tee "$W/report.json.txt"
echo '=== TULOKSET LOPPUVAT ==='
