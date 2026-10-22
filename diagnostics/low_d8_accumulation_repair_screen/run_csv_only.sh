#!/usr/bin/env bash
# Read ONLY the 2026-10-22 archive CSVs after the SHA256 locks are checked.
set -Eeuo pipefail
umask 077
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd -- "$HERE/../.." && pwd -P)"
BRANCH='codex/low-flat-increment-offline-audit-v1'
if [[ $# != 1 || "$1" != /* ]]; then
  echo 'STOP: SUPPLY_ABSOLUTE_EXISTING_CSV_ARCHIVE_DIRECTORY' >&2; exit 1
fi
if [[ ! "${MM_EXPECTED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'STOP: MM_EXPECTED_COMMIT_MISSING_OR_MALFORMED' >&2; exit 1
fi
if [[ "$(git -C "$REPO" rev-parse HEAD)" != "$MM_EXPECTED_COMMIT" ||
      "$(git -C "$REPO" branch --show-current)" != "$BRANCH" ||
      "$(git -C "$REPO" remote get-url origin)" != 'https://github.com/annasuuronen/MaaltaMerelle.git' ||
      -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo 'STOP: WRONG_OR_DIRTY_CHECKOUT' >&2; exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'STOP: PYTHON3_MISSING' >&2; exit 1
fi
export PYTHONDONTWRITEBYTECODE=1
python3 -B "$HERE/audit_flat_increment.py" --selftest
python3 -B "$HERE/audit_flat_increment.py" --work-dir "$1"
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo 'STOP: SOURCE_FILES_MODIFIED' >&2; exit 1
fi
