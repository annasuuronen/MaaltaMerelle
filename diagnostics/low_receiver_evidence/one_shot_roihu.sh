#!/usr/bin/env bash
# One-shot bounded OFFLINE tests only. No real CSC raster/sample reading.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd -- "$HERE/../.." && pwd -P)"
EXPECTED_PR22_LOCK_SHA256="965eec1ea145adc346e52413f2539ec9fe17d82eeab7cf709fafa37f7696bf57"
BRANCH="codex/low-pr22-receiver-evidence-one-shot-v1"
if [[ "$(git -C "$REPO" remote get-url origin)" != "https://github.com/annasuuronen/MaaltaMerelle.git" ]]; then
  echo "STOP: ORIGIN_MISMATCH" >&2; exit 1
fi
if [[ "$(git -C "$REPO" branch --show-current)" != "$BRANCH" ]]; then
  echo "STOP: WRONG_BRANCH" >&2; exit 1
fi
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo "STOP: DIRTY_CHECKOUT" >&2; exit 1
fi
if ! command -v sha256sum >/dev/null || [[ "$(sha256sum "$REPO/diagnostics/land_network_topology/low_boundary_receivers_targets.csv" | cut -d ' ' -f 1)" != "$EXPECTED_PR22_LOCK_SHA256" ]]; then
  echo "STOP: ORIGINAL_PR22_CSV_LOCK_MISMATCH" >&2; exit 1
fi
if ! command -v timeout >/dev/null || ! command -v python3 >/dev/null; then
  echo "STOP: PYTHON_OR_TIMEOUT_MISSING" >&2; exit 1
fi
if ! command -v Rscript >/dev/null; then
  if command -v module >/dev/null 2>&1; then
    module load r-env/461
  else
    echo "STOP: RSCRIPT_MISSING (load CSC r-env/461)" >&2; exit 1
  fi
fi
Rscript --vanilla -e 'stopifnot(requireNamespace("terra", quietly=TRUE))' >/dev/null
cd "$REPO"
echo "========== TULOKSET ALKAVAT =========="
echo "MODE=OFFLINE_ONE_SHOT_NO_REAL_RASTER_READ NO_DOWNSTREAM_TRACE"
echo "CHECKOUT=$(git rev-parse HEAD) PR22_CSV_SHA256=$EXPECTED_PR22_LOCK_SHA256"
echo "TEST=PR22_OBSERVED_TRANSCRIPT_AND_NEGATIVES"
timeout 45s python3 "$HERE/test_observed_receivers.py"
echo "TEST=PR22_SYNTHETIC_TERRA_AND_CLI_COMPATIBILITY"
# Existing test reads only temporary small synthetic rasters and VRT metadata.
timeout 180s Rscript --vanilla "$REPO/diagnostics/land_network_topology/test_boundary_receivers.R"
if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
  echo "STOP: POST_TEST_REPO_CHANGED" >&2; exit 1
fi
echo "RESULT=PASS_NO_HYDROLOGICAL_APPROVAL"
echo "hydrological_validation=NOT_ASSESSED channel_interpretation=NOT_ASSESSED"
echo "MODERATE=REVIEW_REQUIRED NATIONAL=LOCKED"
echo "========== TULOKSET LOPPUVAT =========="
