#!/usr/bin/env bash
# MaaltaMerelle: non-destructive Whitebox 02B diagnosis on Roihu.
# Usage: bash thisfile check|submit|status
# DOES NOT modify GitHub code or existing 01/02 hydrology results.
set -euo pipefail

BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
HYDRO="$BASE/hydro_01_02"
CODE=/projappl/project_2004707/MaaltaMerelle
PROBE="$HYDRO/d8_diagnostic"
JOBFILE="$PROBE/probe.jobid"
JOBSCRIPT="$PROBE/probe_moderate.sbatch"
EXPECTED_COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
IDS=(E200000_N6900000 E0510000_N7620000 E0560000_N7690000 TEST_SULKU_11)
REQUIRED=(land_dem_raw_FLT8S.tif land_dem_filled_FLT8S.tif routing_surface_land_water_FLT8S.tif routing_surface_water_storage_FLT8S.tif)

diagnose() {
  echo '=== CSC INPUTS AND INTERMEDIATE OUTPUTS (READ-ONLY) ==='
  test -d "$CODE/.git" || { echo 'ERROR: Git directory missing' >&2; exit 1; }
  sha=$(git -C "$CODE" rev-parse HEAD)
  echo "CODE_COMMIT=$sha"
  [[ "$sha" == "$EXPECTED_COMMIT" ]] || { echo 'STOP: unexpected source version' >&2; exit 1; }
  for id in "${IDS[@]}"; do
    d="$HYDRO/runs/$id/02_baseline"
    echo "--- $id ---"
    for f in "${REQUIRED[@]}"; do
      if [[ -s "$d/$f" ]]; then
        stat -c '%n %s bytes' "$d/$f"
      else
        echo "MISSING: $d/$f"
        if [[ "$id" == E0510000_N7620000 ]]; then return 1; fi
      fi
    done
    if [[ -s "$d/d8_pointer_land_water_FLT8S.tif" ]]; then
      echo 'D8 final: PRESENT'
    else
      echo 'D8 final: MISSING'
    fi
  done
  echo '=== HISTORICAL SLURM STEPS ==='
  sacct -j 2264131 --format=JobID,JobName,State,Elapsed,TotalCPU,MaxRSS 2>&1 || true
  echo '=== LAST 02B MESSAGES ==='
  for i in 1 2 3; do
    log="$HYDRO/logs/hydro_2264131_${i}.log"
    if [[ -f "$log" ]]; then
      echo "--- task $i ---"
      grep -E '02B:|TIME LIMIT|error:|Error|Terminated' "$log" | tail -n 8 || true
    fi
  done
}

submit() {
  diagnose
  command -v sbatch >/dev/null || { echo 'STOP: sbatch not found' >&2; exit 1; }
  [[ ! -e "$JOBFILE" ]] || { echo "STOP: prior diagnostic job recorded in $JOBFILE; use status" >&2; exit 1; }
  mkdir -p "$PROBE"
  [[ ! -e "$JOBSCRIPT" ]] || { echo 'STOP: diagnostic batch file already exists' >&2; exit 1; }
  cat > "$JOBSCRIPT" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_d8_probe
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=00:25:00
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/d8_diagnostic/probe_%j.log
set -euo pipefail

BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
HYDRO="$BASE/hydro_01_02"
CODE=/projappl/project_2004707/MaaltaMerelle
DIAG="$HYDRO/d8_diagnostic"
INPUT="$HYDRO/runs/E0510000_N7620000/02_baseline/routing_surface_land_water_FLT8S.tif"
OUTPUT="$DIAG/moderate_d8_whitebox_probed.tif"
[[ $(git -C "$CODE" rev-parse HEAD) == 4bbf22bb39181c8a4c27ebc3e2769766043115b8 ]]
[[ -s "$INPUT" ]]
[[ ! -e "$OUTPUT" ]] || { echo "STOP: $OUTPUT already exists; refusing to overwrite" >&2; exit 1; }

module load r-env/461
export R_LIBS=/projappl/project_2004707/project_rpackages_461
export R_WHITEBOX_EXE_PATH=/projappl/project_2004707/whitebox/WBT/whitebox_tools
export R_WHITEBOX_MAX_PROCS=1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export DIAG_DEM="$INPUT" DIAG_OUT="$OUTPUT"
echo "=== D8 PROBE START $(date -u +%FT%TZ) node=$(hostname) job=$SLURM_JOB_ID ==="
echo 'Test: Whitebox D8Pointer ONLY, MODERATE. Prior hydrology outputs are read-only.'
Rscript --no-save -e '
  suppressPackageStartupMessages(library(terra))
  suppressPackageStartupMessages(library(whitebox))
  source_dem <- Sys.getenv("DIAG_DEM")
  target <- Sys.getenv("DIAG_OUT")
  x <- terra::rast(source_dem)
  stopifnot(terra::nrow(x)==6000L, terra::ncol(x)==6000L, terra::nlyr(x)==1L)
  cat("Input raster metadata OK:", terra::ncell(x), "cells; WBT", as.character(packageVersion("whitebox")), "\n")
  print(system.time(whitebox::wbt_d8_pointer(dem=source_dem, output=target, esri_pntr=FALSE, verbose_mode=TRUE)))
  stopifnot(file.exists(target), file.info(target)$size > 0)
  y <- terra::rast(target)
  stopifnot(terra::compareGeom(x,y,stopOnError=FALSE))
  cat("D8_POINTER_PROBE_PASS: output readable and geometry matches input\n")
'
echo "=== D8 PROBE FINISHED $(date -u +%FT%TZ) ==="
SBATCH
  bash -n "$JOBSCRIPT"
  job=$(sbatch --parsable "$JOBSCRIPT")
  job=${job%%;*}
  echo "$job" > "$JOBFILE"
  echo "SUBMITTED_D8_DIAGNOSTIC_JOB=$job"
  echo "Diagnostic log: $PROBE/probe_${job}.log"
  echo 'The probe has a 25-minute limit. It does not rerun stages 01/02.'
}

status() {
  [[ -s "$JOBFILE" ]] || { echo "No diagnostic job yet. Run: bash $0 submit"; exit 0; }
  job=$(cat "$JOBFILE")
  echo "=== DIAGNOSTIC JOB $job ==="
  sacct -j "$job" --format=JobID,State,Elapsed,TotalCPU,MaxRSS,ExitCode || true
  echo '=== LATEST LOG LINES ==='
  log="$PROBE/probe_${job}.log"
  if [[ -f "$log" ]]; then tail -n 65 "$log"; else echo 'Log not created yet (PENDING?)'; fi
  if [[ -s "$PROBE/moderate_d8_whitebox_probed.tif" ]]; then
    echo 'Probe raster exists; see log for QA and Slurm COMPLETED.'
  fi
}

case "${1:-}" in
  check) diagnose ;;
  submit) submit ;;
  status) status ;;
  *) echo "Usage: bash ${0##*/} check|submit|status" >&2; exit 2 ;;
esac
