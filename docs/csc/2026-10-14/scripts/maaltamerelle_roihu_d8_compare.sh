#!/usr/bin/env bash
# MaaltaMerelle 4bbf22b: WhiteboxTools D8Pointer diagnostic comparison.
# Usage: bash thisfile submit | status
# Three NON-DESTRUCTIVE Slurm jobs; does not edit GitHub sources or prior outputs.
set -euo pipefail

ROOT=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02
REPO=/projappl/project_2004707/MaaltaMerelle
COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
INPUT="$ROOT/runs/E0510000_N7620000/02_baseline/routing_surface_land_water_FLT8S.tif"
WHITEBOX=/projappl/project_2004707/whitebox/WBT/whitebox_tools
OUTROOT="$ROOT/d8_compare_20261014"
JOBSCRIPT="$OUTROOT/compare.sbatch"
JOBIDFILE="$OUTROOT/compare.jobid"

fail() { echo "STOP: $*" >&2; exit 1; }

check() {
  [[ -s "$INPUT" ]] || fail "Missing original MODERATE input: $INPUT"
  [[ -x "$WHITEBOX" ]] || fail "Whitebox executable missing: $WHITEBOX"
  [[ -d "$REPO/.git" ]] || fail "Git repo missing"
  [[ "$(git -C "$REPO" rev-parse HEAD)" == "$COMMIT" ]] || fail "Unexpected code commit"
  [[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]] || fail "Tracked code modified"
  command -v sbatch >/dev/null || fail "sbatch not found"
  echo "PRECHECK PASS: code $COMMIT; input and Whitebox available"
}

submit() {
  check
  [[ ! -e "$OUTROOT" ]] || fail "Comparison directory already exists: $OUTROOT (use status; do not resubmit)"
  mkdir -p "$OUTROOT"
  cat > "$JOBSCRIPT" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_d8_comparison
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --array=0-2%2
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/d8_compare_20261014/compare_%A_%a.log
set -euo pipefail

ROOT=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02
INPUT="$ROOT/runs/E0510000_N7620000/02_baseline/routing_surface_land_water_FLT8S.tif"
WHITEBOX=/projappl/project_2004707/whitebox/WBT/whitebox_tools
DEST="$ROOT/d8_compare_20261014"
EXPECTED_COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
[[ "$(git -C /projappl/project_2004707/MaaltaMerelle rev-parse HEAD)" == "$EXPECTED_COMMIT" ]]
[[ -s "$INPUT" && -x "$WHITEBOX" ]]
case "${SLURM_ARRAY_TASK_ID:?Missing Slurm task index}" in
  0) MODE=shared_1; N=1; STORAGE=shared ;;
  1) MODE=shared_4; N=4; STORAGE=shared ;;
  2) MODE=local_1;  N=1; STORAGE=local  ;;
  *) echo 'Invalid array task' >&2; exit 2 ;;
esac
MODEDIR="$DEST/$MODE"
[[ ! -e "$MODEDIR" ]] || { echo "STOP: output already exists: $MODEDIR" >&2; exit 1; }
mkdir -p "$MODEDIR"
RESULT="$MODEDIR/result.txt"
echo "mode=$MODE" > "$RESULT"
echo "job=${SLURM_JOB_ID}" >> "$RESULT"
echo "start_utc=$(date -u +%FT%TZ)" >> "$RESULT"
echo "host=$(hostname)" >> "$RESULT"
echo "input=$INPUT" >> "$RESULT"
echo "workers=$N" >> "$RESULT"
echo "storage=$STORAGE" >> "$RESULT"
echo "command=whitebox_tools --run=D8Pointer" >> "$RESULT"

# Use Roihu-provided node-local TMPDIR (do not replace with a shared directory).
if [[ "$STORAGE" == local ]]; then
  [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]] || { echo 'TMPDIR is not available' >&2; exit 1; }
  LOCAL=$(mktemp -d "$TMPDIR/mm_d8_compare_${SLURM_JOB_ID}_XXXXXX")
  trap 'rm -rf -- "$LOCAL"' EXIT
  cp -- "$INPUT" "$LOCAL/input.tif"
  DEM="$LOCAL/input.tif"
  OUT="$LOCAL/d8_pointer.tif"
else
  DEM="$INPUT"
  OUT="$MODEDIR/d8_pointer.tif"
fi
printf '=== %s / workers %d / storage %s / node %s / %s ===\n' "$MODE" "$N" "$STORAGE" "$(hostname)" "$(date -u +%FT%TZ)"
echo "TMPDIR=${TMPDIR:-unset}"
df -h "$DEM" "$MODEDIR" 2>/dev/null || true

# Direct executable, without the R wrapper, to separate possible wrapper issues.
# A 12-min timeout bounds each diagnostic, leaving time for final logs and copying.
set +e
timeout --signal=TERM --kill-after=15s 12m "$WHITEBOX" --run=D8Pointer --dem="$DEM" --output="$OUT" -v --max_procs="$N"
RC=$?
set -e
echo "whitebox_exit=$RC" >> "$RESULT"
echo "finish_utc=$(date -u +%FT%TZ)" >> "$RESULT"
echo "whitebox_exit=$RC"

if [[ "$RC" -eq 124 || "$RC" -eq 137 ]]; then
  echo 'result=TIMEOUT' >> "$RESULT"
  echo "DIAG_RESULT=$MODE: TIMEOUT (no baseline files changed)"
  exit 124
elif [[ "$RC" -ne 0 ]]; then
  echo 'result=WHITEBOX_FAILED' >> "$RESULT"
  echo "DIAG_RESULT=$MODE: WHITEBOX_FAILED (exit $RC)"
  exit "$RC"
fi

if [[ ! -s "$OUT" ]]; then
  echo 'result=EMPTY_OUTPUT' >> "$RESULT"
  echo "DIAG_RESULT=$MODE: EMPTY_OUTPUT"
  exit 1
fi

# Metadata QA; success does not yet prove scientific equivalence.
module load r-env/461
export R_LIBS=/projappl/project_2004707/project_rpackages_461
if ! Rscript --no-save -e 'suppressPackageStartupMessages(library(terra)); a<-rast(commandArgs(TRUE)[1]); b<-rast(commandArgs(TRUE)[2]); stopifnot(nrow(b)==6000L, ncol(b)==6000L, nlyr(b)==1L, compareGeom(a,b,stopOnError=FALSE)); cat("D8_METADATA_QA_PASS\n")' "$DEM" "$OUT"; then
  echo 'result=METADATA_QA_FAILED' >> "$RESULT"
  echo "DIAG_RESULT=$MODE: METADATA_QA_FAILED"
  exit 1
fi

if [[ "$STORAGE" == local ]]; then
  cp -- "$OUT" "$MODEDIR/d8_pointer.tif.part"
  mv "$MODEDIR/d8_pointer.tif.part" "$MODEDIR/d8_pointer.tif"
fi
stat -c 'output_size_bytes=%s' "$MODEDIR/d8_pointer.tif" >> "$RESULT"
echo 'result=PASS_METADATA_ONLY' >> "$RESULT"
echo "DIAG_RESULT=$MODE: PASS_METADATA_ONLY"
SBATCH
  bash -n "$JOBSCRIPT" || fail 'Generated sbatch script has Bash syntax errors'
  # Do not overlap with prior probe, if still running. The old job need not succeed.
  dependency=()
  if squeue -h -j 2285854 | grep -q .; then
    dependency=(--dependency=afterany:2285854)
    echo 'Existing diagnostic 2285854 still active; array will wait for it to finish.'
  fi
  job=$(sbatch --parsable "${dependency[@]}" "$JOBSCRIPT")
  job=${job%%;*}
  printf '%s\n' "$job" > "$JOBIDFILE"
  echo "SUBMITTED_D8_COMPARISON=$job"
  echo 'Modes: 0=shared_1, 1=shared_4, 2=local_1; max two tasks concurrently.'
  echo "Logs: $OUTROOT/compare_${job}_*.log"
  echo "Check: bash $0 status"
}

status() {
  [[ -s "$JOBIDFILE" ]] || fail 'No comparison job recorded; run submit first.'
  job=$(<"$JOBIDFILE")
  echo "=== D8 COMPARISON $job ==="
  sacct -j "$job" -X --format=JobID,State,Elapsed,TotalCPU,MaxRSS,ExitCode || true
  squeue -j "$job" -o '%.18i %.10T %.10M %R' 2>/dev/null || true
  for mode in shared_1 shared_4 local_1; do
    echo "=== $mode ==="
    if [[ -s "$OUTROOT/$mode/result.txt" ]]; then cat "$OUTROOT/$mode/result.txt"; else echo 'No result yet'; fi
  done
  echo '=== LAST LOG LINES ==='
  for i in 0 1 2; do
    log="$OUTROOT/compare_${job}_${i}.log"
    if [[ -f "$log" ]]; then echo "--- task $i ---"; tail -n 14 "$log"; fi
  done
}

case "${1:-}" in
  submit) submit ;;
  status) status ;;
  check) check ;;
  *) echo "Usage: bash $0 check|submit|status" >&2; exit 2 ;;
esac
