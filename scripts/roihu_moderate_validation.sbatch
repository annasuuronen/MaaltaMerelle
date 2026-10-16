#!/usr/bin/env bash
#SBATCH --job-name=mm_mod_review
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=02:00:00
# Read-only validation; NO national or full hydrology pipeline execution.
# Submit explicitly with: sbatch scripts/roihu_moderate_validation.sbatch
set -euo pipefail

CODE="${HYDRO_CODE_ROOT:-/projappl/project_2004707/MaaltaMerelle}"
SRC="/scratch/project_2004707/pienvedet/csc_validation_4bbf22b"
BASELINE="${HYDRO_REVIEW_BASELINE:-$SRC/hydro_01_02/moderate_resume_20261014_v2/run/02_baseline}"
LAKE="${HYDRO_REVIEW_LAKE_ID:-$SRC/inputs/E0510000_N7620000/ranta10_lake_id.tif}"
REPORT_BASE="${HYDRO_REVIEW_REPORT_ROOT:-$SRC/hydro_01_02/moderate_scientific_review}"
JOB="${SLURM_JOB_ID:-manual}"
REPORT="$REPORT_BASE/job_$JOB"

if [[ ! -d "$CODE/.git" || ! -s "$BASELINE/02D_lake_depression_component_summary.csv" || ! -s "$LAKE" ]]; then
  echo "STOP: checkout or input missing; no computation performed" >&2
  exit 2
fi
if [[ -e "$REPORT" ]]; then
  echo "STOP: output directory already exists; refusing overwrite: $REPORT" >&2
  exit 2
fi
mkdir -p "$REPORT"
cd "$CODE"

module load r-env/461
export R_LIBS="/projappl/project_2004707/project_rpackages_461"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export R_WHITEBOX_MAX_PROCS=1

{
  echo "=== ENVIRONMENT AND PROVENANCE ==="
  date -u +"UTC_START=%Y-%m-%dT%H:%M:%SZ"
  echo "SCIENTIFIC_STATUS=REVIEW_REQUIRED"
  echo "NATIONAL=LOCKED"
  echo "CODE_ROOT=$CODE"
  echo "BASELINE=$BASELINE"
  echo "LAKE_ID=$LAKE"
  echo "JOB=$JOB"
  git rev-parse HEAD
  git status --short
  Rscript --version
  Rscript --vanilla -e 'cat("terra=",as.character(packageVersion("terra")),"\n")'
  sha256sum "$BASELINE/routing_surface_land_water_FLT8S.tif" "$BASELINE/routing_surface_water_storage_FLT8S.tif" "$BASELINE/d8_pointer_land_water_FLT8S.tif" "$LAKE"
} >"$REPORT/provenance.txt" 2>&1

# These diagnostics are independent and do not change the existing data.
# Individual step outputs are captured separately, including errors.
execute() {
  local label="$1"
  local script="$2"
  local rc=0
  echo "RUN $label"
  Rscript --vanilla "$script" "$BASELINE" "$LAKE" >"$REPORT/$label.log" 2>&1 || rc=$?
  echo "$label exit=$rc" >>"$REPORT/steps.txt"
  if (( rc != 0 )); then
    echo "ERROR: $label exit=$rc; see $REPORT/$label.log" >&2
    exit "$rc"
  fi
}
execute "spill_d8" "scripts/audit_moderate_spill_d8_readonly.R"
execute "lake_geometry" "scripts/audit_moderate_lake_geometry_readonly.R"

{
  echo "REPORT_ROOT=$REPORT"
  cat "$REPORT/steps.txt"
  grep -E '^(LAKES |MISMATCH_CLASS|MISMATCH_LAKES|SPILL_RAISED|PRODUCTION_02D5_GATE_PASS|RETURN_TO_SOURCE_LAKE|[[:space:]]+159|[[:space:]]+3|TOUCHES_DOMAIN_EDGE|HAS_NODATA_OUTSIDE_SHORE|NONCONSTANT_LAKE_Z|HAS_CHANGED_SOURCE_STORAGE|SCIENTIFIC_STATUS|NATIONAL_LOCKED)' "$REPORT/spill_d8.log" "$REPORT/lake_geometry.log" || true
  echo "VALIDATION_DIAGNOSTICS_COMPLETE=true"
  echo "SCIENTIFIC_STATUS=REVIEW_REQUIRED"
  echo "NATIONAL=LOCKED"
} >"$REPORT/summary.txt"
cat "$REPORT/summary.txt"
