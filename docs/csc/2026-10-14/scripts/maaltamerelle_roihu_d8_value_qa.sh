#!/usr/bin/env bash
# MaaltaMerelle / Roihu: D8 pointer value-level QA for two successful MODERATE probes.
# Does not modify the source repository or any baseline hydrology outputs.
# Usage: bash maaltamerelle_roihu_d8_value_qa.sh check|submit|status
set -euo pipefail

ROOT=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02
REPO=/projappl/project_2004707/MaaltaMerelle
COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
INPUT="$ROOT/runs/E0510000_N7620000/02_baseline/routing_surface_land_water_FLT8S.tif"
A="$ROOT/d8_compare_20261014/shared_1/d8_pointer.tif"
C="$ROOT/d8_compare_20261014/local_1/d8_pointer.tif"
DEST="$ROOT/d8_value_qa_20261014"
JOBFILE="$DEST/qa.jobid"
BATCH="$DEST/qa.sbatch"
OUT="$DEST/results"

fail() { echo "STOP: $*" >&2; exit 1; }

check() {
  [[ "$(git -C "$REPO" rev-parse HEAD)" == "$COMMIT" ]] || fail 'Wrong repository commit'
  [[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]] || fail 'Tracked source files changed'
  for f in "$INPUT" "$A" "$C"; do [[ -s "$f" ]] || fail "Missing or empty: $f"; done
  for m in shared_1 local_1; do
    grep -Fxq 'result=PASS_METADATA_ONLY' "$ROOT/d8_compare_20261014/$m/result.txt" || fail "$m did not pass previous metadata QA"
  done
  [[ ! -e "$ROOT/runs/E0510000_N7620000/02_baseline/d8_pointer_land_water_FLT8S.tif" ]] || fail 'Baseline D8 pointer already exists: do not duplicate/overwrite'
  echo 'PRECHECK_PASS: source commit, original input, two successful independent probe results, baseline pointer still absent'
  echo 'SHA256 of comparison rasters (bytes may differ even when values agree):'
  sha256sum "$A" "$C"
}

submit() {
  check
  command -v sbatch >/dev/null || fail 'sbatch missing'
  [[ ! -e "$DEST" ]] || fail "Destination already exists: $DEST. Use status."
  mkdir -p "$OUT"
  cat > "$OUT/verify.R" <<'RSCRIPT'
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==4L)
input <- rast(args[1]); a <- rast(args[2]); c <- rast(args[3]); dest <- args[4]
stopifnot(nlyr(input)==1L, nrow(input)==6000L, ncol(input)==6000L)
stopifnot(nlyr(a)==1L, nlyr(c)==1L)
stopifnot(compareGeom(input,a,stopOnError=FALSE),compareGeom(input,c,stopOnError=FALSE))
cat('D8_QA_GEOMETRY_PASS: input, shared_1, local_1 all have matching CRS/resolution/extent\n')
allowed <- c(0,1,2,4,8,16,32,64,128)
counts <- setNames(rep(0, length(allowed)),as.character(allowed))
na_in <- 0; na_a <- 0; na_c <- 0; mismatches <- 0; invalid <- 0; input_mask_mismatch <- 0
readStart(input); readStart(a); readStart(c)
for (row in seq(1L,nrow(input),by=250L)) {
  nr <- min(250L, nrow(input)-row+1L)
  vin <- as.numeric(readValues(input,row=row,nrows=nr,mat=FALSE))
  va <- as.numeric(readValues(a,row=row,nrows=nr,mat=FALSE))
  vc <- as.numeric(readValues(c,row=row,nrows=nr,mat=FALSE))
  stopifnot(length(vin)==length(va),length(va)==length(vc))
  ia <- is.na(va); ic <- is.na(vc)
  na_in <- na_in+sum(is.na(vin)); na_a <- na_a+sum(ia); na_c <- na_c+sum(ic)
  mismatches <- mismatches+sum(xor(ia,ic))+sum(!ia & !ic & va != vc)
  valid <- !ia
  invalid <- invalid+sum(!is.finite(va[valid]) | !(va[valid] %in% allowed))
  input_mask_mismatch <- input_mask_mismatch + sum(xor(is.na(vin),ia))
  for (code in allowed) counts[as.character(code)] <- counts[as.character(code)] + sum(va[valid]==code)
  cat(sprintf('rows %d-%d verified\n',row,row+nr-1L))
  flush.console()
}
readStop(input); readStop(a); readStop(c)
qa <- data.frame(metric=c('total_cells','source_na','shared_pointer_na','local_pointer_na','value_mismatches_shared_vs_local','invalid_d8_codes_shared','input_vs_pointer_na_mask_mismatches',paste0('d8_code_',allowed)),
                 value=c(ncell(input),na_in,na_a,na_c,mismatches,invalid,input_mask_mismatch,unname(counts)), stringsAsFactors=FALSE)
write.csv(qa,dest,row.names=FALSE)
print(qa,row.names=FALSE)
if (mismatches != 0 || invalid != 0) stop('D8_VALUE_QA_FAILED: values differ or invalid D8 direction codes')
cat('D8_VALUE_QA_PASS: all 36 million D8 values agree across two probes; codes valid. Scientific reference comparison remains separate.\n')
RSCRIPT
  cat > "$BATCH" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_d8_value_qa
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=12G
#SBATCH --time=00:20:00
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/d8_value_qa_20261014/qa_%j.log
set -euo pipefail
ROOT=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02
REPO=/projappl/project_2004707/MaaltaMerelle
D="$ROOT/d8_value_qa_20261014/results"
BASE="$ROOT/runs/E0510000_N7620000/02_baseline"
INPUT="$BASE/routing_surface_land_water_FLT8S.tif"
A="$ROOT/d8_compare_20261014/shared_1/d8_pointer.tif"
C="$ROOT/d8_compare_20261014/local_1/d8_pointer.tif"
[[ "$(git -C "$REPO" rev-parse HEAD)" == 4bbf22bb39181c8a4c27ebc3e2769766043115b8 ]]
[[ -s "$A" && -s "$C" && -s "$INPUT" ]]
[[ ! -e "$BASE/d8_pointer_land_water_FLT8S.tif" ]] || { echo 'Baseline D8 already present, abort.' >&2; exit 1; }
module load r-env/461
export R_LIBS=/projappl/project_2004707/project_rpackages_461
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
cd "$REPO"
echo "START $(date -u +%FT%TZ) node=$(hostname) job=$SLURM_JOB_ID"
Rscript --no-save "$D/verify.R" "$INPUT" "$A" "$C" "$D/qa.csv"
echo 'D8_QA_JOB_COMPLETED; no baseline outputs changed'
SBATCH
  bash -n "$BATCH" || fail 'Batch script contains syntax error'
  job=$(sbatch --parsable "$BATCH")
  job=${job%%;*}
  printf '%s\n' "$job" > "$JOBFILE"
  echo "SUBMITTED_D8_VALUE_QA=$job"
  echo "Check: bash $0 status"
}

status() {
  [[ -s "$JOBFILE" ]] || fail 'No QA job recorded. Use submit first.'
  local job
  job=$(<"$JOBFILE")
  sacct -j "$job" -X --format=JobID,State,Elapsed,ExitCode,MaxRSS || true
  if [[ -f "$DEST/qa_${job}.log" ]]; then tail -n 35 "$DEST/qa_${job}.log"; fi
  if [[ -s "$OUT/qa.csv" ]]; then echo "QA report: $OUT/qa.csv"; fi
}

case "${1:-}" in
  check) check ;;
  submit) submit ;;
  status) status ;;
  *) echo "Usage: bash $0 check|submit|status" >&2; exit 2 ;;
esac
