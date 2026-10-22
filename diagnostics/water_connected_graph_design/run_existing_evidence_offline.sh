#!/usr/bin/env bash
# Offline LOW existing-evidence inventory only: no TIFF, GDAL, R, Slurm or Whitebox.
set -Eeuo pipefail
umask 077
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd -- "$HERE/../.." && pwd -P)"
EXPECTED_BRANCH=codex/water-connected-existing-csv-evidence-inventory-v1
if [[ $# != 1 || "$1" != /* || ! -d "$1" ]]; then
  echo 'STOP: PROVIDE_EXISTING_ABSOLUTE_02_BASELINE_CSV_DIRECTORY' >&2; exit 1
fi
if [[ ! "${MM_EXPECTED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'STOP: MM_EXPECTED_COMMIT_REQUIRED' >&2; exit 1
fi
if [[ "$(git -C "$REPO" rev-parse HEAD)" != "$MM_EXPECTED_COMMIT" ||
      "$(git -C "$REPO" branch --show-current)" != "$EXPECTED_BRANCH" ||
      "$(git -C "$REPO" remote get-url origin)" != 'https://github.com/annasuuronen/MaaltaMerelle.git' ||
      -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo 'STOP: GIT_PIN_BRANCH_OR_CLEANLINESS' >&2; exit 1
fi
command -v python3 >/dev/null || { echo 'STOP: PYTHON3_REQUIRED' >&2; exit 1; }
command -v timeout >/dev/null || { echo 'STOP: TIMEOUT_REQUIRED' >&2; exit 1; }
export PYTHONDONTWRITEBYTECODE=1
OUT="$(mktemp -d /scratch/project_2004707/pienvedet/mm_02d02f_inventory.XXXXXXXX)"
echo "INVENTORY_WORK=$OUT"
timeout 20s python3 -B -m unittest discover -s "$HERE" -p 'test_*.py' \
  > "$OUT/synthetic_tests.log" 2>&1 || {
    cat "$OUT/synthetic_tests.log" >&2; echo 'STOP: SYNTHETIC_TESTS_FAILED' >&2; exit 1; }
echo "SYNTHETIC_TESTS=PASS"
tail -n 3 "$OUT/synthetic_tests.log"
timeout 90s python3 -B "$HERE/inventory_existing_evidence.py" \
  --input-dir "$1" --output-dir "$OUT/result" --evidence-label "CSC_EXISTING_CSV_PROVENANCE_NOT_INDEPENDENTLY_VERIFIED"
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo 'STOP: CODE_TREE_CHANGED' >&2; exit 1
fi
echo "INVENTORY_OUTPUT=$OUT/result"
