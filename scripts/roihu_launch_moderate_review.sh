#!/usr/bin/env bash
# One-time, isolated Roihu launcher. No production checkout edits.
# This file is NOT executed automatically. Run only when CSC access is available.
set -euo pipefail
ROOT="/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02"
CHECKOUT_PARENT="$ROOT/moderate_review_checkouts"
mkdir -p "$CHECKOUT_PARENT"
WORK="$(mktemp -d "$CHECKOUT_PARENT/review.XXXXXXXX")"
if [[ ! -d "$WORK" ]]; then echo "STOP: cannot allocate checkout" >&2; exit 2; fi
git clone --quiet --single-branch --depth 1 --branch codex/moderate-02d4-diagnosis \
  https://github.com/annasuuronen/MaaltaMerelle.git "$WORK/MaaltaMerelle"
CODE="$WORK/MaaltaMerelle"
echo "REVIEW_CODE_COMMIT=$(git -C "$CODE" rev-parse HEAD)"
echo "REVIEW_CODE_ROOT=$CODE"
JOB_OUTPUT="$WORK/slurm_%j.out"
sbatch --parsable --chdir="$CODE" --output="$JOB_OUTPUT" \
  --export="ALL,HYDRO_CODE_ROOT=$CODE" "$CODE/scripts/roihu_moderate_validation.sbatch"
echo "ONE_JOB_SUBMITTED; outputs: $JOB_OUTPUT and review_bundle.tar.gz inside the job review directory"
echo "NO_NATIONAL_RUN; NO_PRODUCTION_INPUT_WRITE"
