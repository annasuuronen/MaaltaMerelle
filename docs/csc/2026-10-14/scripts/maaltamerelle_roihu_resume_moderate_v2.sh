#!/usr/bin/env bash
# MaaltaMerelle / Roihu: FIXED v2 isolated 02B-02F continuation for MODERATE after D8 QA.
# No GitHub changes; never overwrites original 01/02A/LOW/NATURAL/SULKU outputs.
# Usage: bash ~/maaltamerelle_roihu_resume_moderate_v2.sh check|submit|status
set -euo pipefail

BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
ROOT="$BASE/hydro_01_02"
CODE=/projappl/project_2004707/MaaltaMerelle
COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
ID=E0510000_N7620000
ORIGINAL="$ROOT/runs/$ID"
SOURCE="$BASE/inputs/$ID"
D8_TEST="$ROOT/d8_compare_20261014/shared_1/d8_pointer.tif"
D8_LOCAL="$ROOT/d8_compare_20261014/local_1/d8_pointer.tif"
QA_DIR="$ROOT/d8_value_qa_20261014"
DEST="$ROOT/moderate_resume_20261014_v2"
RUN="$DEST/run"
BATCH="$DEST/resume.sbatch"
JOBFILE="$DEST/resume.jobid"
LOGFILE="$DEST/resume.log"
REPORT="$DEST/validated_d8_report.csv"
PASS="$DEST/CSC_MODERATE_RESUME_PASS.txt"
EXPECTED_D8_SHA=816f6c1b80a8e1a03394bbc13927de1a1d7a053193357880c7c23b4b6d763281

fail() { printf 'STOP: %s\n' "$*" >&2; exit 1; }

check() {
  echo '=== MAALTAMERELLE MODERATE 02B-02F RESUME PRECHECK ==='
  [[ -d "$CODE/.git" ]] || fail "Git repository missing: $CODE"
  [[ "$(git -C "$CODE" rev-parse HEAD)" == "$COMMIT" ]] || fail 'Repository commit differs from validated reference'
  [[ -z "$(git -C "$CODE" status --porcelain --untracked-files=no)" ]] || fail 'Tracked source files are modified'
  [[ -s "$SOURCE/dem_12km_rumpukorjattu.tif" ]] || fail 'Original DEM missing'
  [[ -s "$SOURCE/ranta10_water_class.tif" ]] || fail 'RANTA10 water class missing'
  [[ -s "$SOURCE/ranta10_lake_id.tif" ]] || fail 'RANTA10 lake ID missing'
  [[ -s "$ORIGINAL/01_inputs/ranta10_lake_elevation_m.tif" ]] || fail 'Stage 01 lake elevations missing'
  [[ -s "$ORIGINAL/01_inputs/01_input_QA.csv" ]] || fail 'Stage 01 QA missing'
  for name in land_dem_raw_FLT8S.tif land_dem_filled_FLT8S.tif routing_surface_land_water_FLT8S.tif routing_surface_water_storage_FLT8S.tif; do
    [[ -s "$ORIGINAL/02_baseline/$name" ]] || fail "02A raster missing: $name"
  done
  [[ ! -e "$ORIGINAL/02_baseline/d8_pointer_land_water_FLT8S.tif" ]] || fail 'Original baseline pointer already exists; inspect before proceeding'
  [[ ! -e "$ORIGINAL/CSC_01_02_PASS.txt" ]] || fail 'Original already marked PASS'
  [[ -s "$D8_TEST" && -s "$D8_LOCAL" ]] || fail 'Successful D8 probe files missing'
  printf '%s  %s\n' "$EXPECTED_D8_SHA" "$D8_TEST" | sha256sum -c - || fail 'Probe hash mismatch (shared_1)'
  printf '%s  %s\n' "$EXPECTED_D8_SHA" "$D8_LOCAL" | sha256sum -c - || fail 'Probe hash mismatch (local_1)'
  [[ -s "$QA_DIR/results/qa.csv" ]] || fail 'D8 value QA report missing'
  [[ -s "$QA_DIR/qa.jobid" ]] || fail 'D8 QA job ID missing'
  local qajob qastate
  qajob=$(<"$QA_DIR/qa.jobid")
  qastate=$(sacct -j "$qajob" -X --noheader -P --format=State 2>/dev/null | head -1 | cut -d'|' -f1)
  [[ "$qastate" == COMPLETED ]] || fail "D8 value QA Slurm job not COMPLETED: $qajob state=$qastate"
  grep -Fq 'D8_VALUE_QA_PASS:' "$QA_DIR/qa_${qajob}.log" || fail 'D8 QA PASS log marker missing'
  command -v sbatch >/dev/null || fail 'Cannot locate sbatch'
  if [[ -e "$DEST" ]]; then
    [[ -f "$JOBFILE" ]] && fail "Resume already submitted: $(cat "$JOBFILE"); run status"
    fail "Destination $DEST exists; inspect before continuing; refusing overwrite"
  fi
  echo 'PRECHECK_PASS_V2: original data + two byte-identical D8 probes + completed all-cell QA; no original files modified'
  echo 'Original outputs and GitHub repository will not be written.'
}

submit() {
  check
  mkdir "$DEST"
  cat > "$DEST/validate_and_convert.R" <<'RSCRIPT'
suppressPackageStartupMessages(library(terra))
a <- commandArgs(trailingOnly=TRUE)
stopifnot(length(a)==4L)
source_file <- a[1]; reference_file <- a[2]; target_file <- a[3]; report_file <- a[4]
src <- rast(source_file)
ref <- rast(reference_file)
stopifnot(nlyr(src)==1L,nlyr(ref)==1L,nrow(src)==6000L,ncol(src)==6000L)
stopifnot(compareGeom(src, ref, stopOnError=FALSE))
stopifnot(!file.exists(target_file))
# The reference_file is the ROUTING SURFACE (elevations), for GEOMETRY only.
# Cell values MUST be compared against src (D8 codes), not ref (elevations).
# Exactly the same output data type and GDAL settings as the pinned 02B pipeline.
writeRaster(src,target_file,overwrite=FALSE,datatype='FLT8S',gdal=c('COMPRESS=DEFLATE','BIGTIFF=YES'))
ptr <- rast(target_file)
stopifnot(compareGeom(src,ptr,stopOnError=FALSE), compareGeom(ref,ptr,stopOnError=FALSE))
valid <- c(0,1,2,4,8,16,32,64,128)
wrong <- 0; invalid <- 0; na_mask <- 0; count <- 0
input_na_mask <- 0
readStart(src); readStart(ptr); readStart(ref)
for (r in seq.int(1L,nrow(src),by=250L)) {
  n <- min(250L,nrow(src)-r+1L)
  aa <- as.numeric(readValues(src,row=r,nrows=n,mat=FALSE))
  bb <- as.numeric(readValues(ptr,row=r,nrows=n,mat=FALSE))
  zz <- as.numeric(readValues(ref,row=r,nrows=n,mat=FALSE))
  stopifnot(length(aa)==length(bb), length(aa)==length(zz))
  ia <- is.na(aa); ib <- is.na(bb); iz <- is.na(zz)
  na_mask <- na_mask + sum(xor(ia,ib))
  input_na_mask <- input_na_mask + sum(xor(ib,iz))
  wrong <- wrong + sum(!ia & !ib & aa!=bb)
  invalid <- invalid + sum(!ib & (!is.finite(bb) | !(bb %in% valid)))
  count <- count + length(aa)
}
readStop(src); readStop(ptr); readStop(ref)
qa <- data.frame(metric=c('n_cells','pointer_value_mismatches','pointer_invalid_codes','pointer_na_mask_mismatches','pointer_vs_surface_na_mask_mismatches'),value=c(count,wrong,invalid,na_mask,input_na_mask))
write.csv(qa, report_file, row.names=FALSE)
print(qa,row.names=FALSE)
stopifnot(count==36000000,wrong==0,invalid==0,na_mask==0,input_na_mask==0)
cat('RESUME_D8_FLT8S_VALUE_QA_PASS\n')
RSCRIPT
  cat > "$BATCH" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_moderate_resume
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=32G
#SBATCH --time=05:00:00
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_resume_20261014_v2/resume.log
set -euo pipefail

BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
ROOT="$BASE/hydro_01_02"
CODE=/projappl/project_2004707/MaaltaMerelle
COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
ID=E0510000_N7620000
ORIGINAL="$ROOT/runs/$ID"
SOURCE="$BASE/inputs/$ID"
DEST="$ROOT/moderate_resume_20261014_v2"
RUN="$DEST/run"
POINTER="$RUN/02_baseline/d8_pointer_land_water_FLT8S.tif"
D8_TEST="$ROOT/d8_compare_20261014/shared_1/d8_pointer.tif"
INPUT="$ORIGINAL/02_baseline/routing_surface_land_water_FLT8S.tif"
PASS="$DEST/CSC_MODERATE_RESUME_PASS.txt"

[[ "$(git -C "$CODE" rev-parse HEAD)" == "$COMMIT" ]] || { echo 'Wrong commit'; exit 1; }
[[ ! -e "$RUN" ]] || { echo 'Resume output already exists; refusing overwrite'; exit 1; }
[[ ! -e "$ORIGINAL/02_baseline/d8_pointer_land_water_FLT8S.tif" ]] || { echo 'Original 02B pointer now exists; stop'; exit 1; }
mkdir -p "$RUN/01_inputs" "$RUN/02_baseline"
echo "RESUME START $(date -u +%FT%TZ) node=$(hostname) job=$SLURM_JOB_ID"
echo 'Copying stage 01 and selected 02A artifacts to an ISOLATED run directory (no modification of originals).'
cp -a "$ORIGINAL/01_inputs/." "$RUN/01_inputs/"
for name in land_dem_raw_FLT8S.tif land_dem_filled_FLT8S.tif routing_surface_land_water_FLT8S.tif routing_surface_water_storage_FLT8S.tif; do
  cp -p "$ORIGINAL/02_baseline/$name" "$RUN/02_baseline/$name"
done
if [[ -s "$ORIGINAL/02_baseline/02A_storage_regression_QA.csv" ]]; then
  cp -p "$ORIGINAL/02_baseline/02A_storage_regression_QA.csv" "$RUN/02_baseline/02A_storage_regression_QA.csv"
fi
for name in land_dem_raw_FLT8S.tif land_dem_filled_FLT8S.tif routing_surface_land_water_FLT8S.tif routing_surface_water_storage_FLT8S.tif; do
  cmp "$ORIGINAL/02_baseline/$name" "$RUN/02_baseline/$name" || { echo "Copied 02A raster changed: $name"; exit 1; }
done

module load r-env/461
export R_LIBS=/projappl/project_2004707/project_rpackages_461
export R_WHITEBOX_EXE_PATH=/projappl/project_2004707/whitebox/WBT/whitebox_tools
export R_WHITEBOX_MAX_PROCS=1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export HYDRO_MODE=CSC_TEST
export HYDRO_PROJECT_ROOT="$CODE"
export HYDRO_TEST_ID="$ID"
export HYDRO_TEST_EXTENT=509000,521000,7619000,7631000
export HYDRO_EXPECTED_LAKES=158
export HYDRO_EXPECTED_RIVER_AREAS=2
export HYDRO_EXPECTED_RIVER_LINES=105
export HYDRO_SOURCE_TEST_ROOT="$SOURCE"
export HYDRO_RUN_ROOT="$RUN"

cd "$CODE"
echo '=== D8 POINTER COPY/CONVERT/VERIFY ==='
Rscript --no-save "$DEST/validate_and_convert.R" "$D8_TEST" "$INPUT" "$POINTER" "$DEST/validated_d8_report.csv"
[[ -s "$POINTER" ]] || { echo 'Prepared D8 pointer missing'; exit 1; }
# The pinned 02B code checks file.exists and OVERWRITE=FALSE, so Whitebox D8Pointer will be skipped.
echo '=== STAGE 02 RESUME: EXISTING 02A + VERIFIED 02B POINTER ==='
Rscript --no-save R/02_build_baseline_hydrology.R

echo '=== PIPELINE QA ==='
# Require the same key markers as the initial full 01/02 Slurm job.
for marker in '02E HARD QA: PASS' '02E CANDIDATE MASK QA: PASS' '02F ROUTE DIAGNOSTIC QA: PASS' '02D.7E HARD QA: PASS'; do
  n=$(grep -Fxc "$marker" "$DEST/resume.log" || true)
  [[ "$n" -eq 1 ]] || { echo "QA marker missing or repeated: $marker count=$n"; exit 1; }
done
[[ -s "$RUN/02_baseline/02F_water_connected_route_QA.csv" ]] || { echo 'Missing 02F QA CSV'; exit 1; }
[[ -s "$DEST/validated_d8_report.csv" ]] || { echo 'Missing validated D8 report'; exit 1; }
{
  echo status=PASS
  echo scope=CSC_MODERATE_resumed_execution_and_QA_markers_not_scientific_equivalence
  echo "source_commit=$COMMIT"
  echo "slurm_job_id=$SLURM_JOB_ID"
  echo "finished_utc=$(date -u +%FT%TZ)"
  echo "isolated_run_root=$RUN"
  echo validated_pointer_all_36m_values=yes
  echo original_baseline_unchanged_by_this_job=yes
} > "$PASS.tmp"
mv "$PASS.tmp" "$PASS"
echo '=== CSC MODERATE RESUME: PASS ==='
SBATCH
  bash -n "$BATCH" || fail 'Generated Slurm script failed bash syntax validation'
  job=$(sbatch --parsable "$BATCH")
  job=${job%%;*}
  printf '%s\n' "$job" > "$JOBFILE"
  echo "SUBMITTED_MODERATE_RESUME_V2=$job"
  echo "ISOLATED_OUTPUT=$RUN"
  echo "LOG=$LOGFILE"
  echo "Check: bash $0 status"
}

status() {
  [[ -s "$JOBFILE" ]] || fail 'No continuation job submitted yet; run check/submit first'
  local job
  job=$(<"$JOBFILE")
  echo "=== MODERATE RESUME SLURM JOB $job ==="
  sacct -j "$job" -X --format=JobID,State,Elapsed,ExitCode,MaxRSS || true
  squeue -j "$job" -o '%.18i %.9T %.10M %R' 2>/dev/null || true
  if [[ -f "$LOGFILE" ]]; then
    echo '=== KEY PHASE MARKERS ==='
    grep -E '^=== (02[BCDEF]|CSC MODERATE|STAGE 02)|^02[A-F].*(QA|PASS|HARD)|RESUME_D8_FLT8S_VALUE_QA_PASS|Error|error|Terminated|TIME LIMIT' "$LOGFILE" | tail -n 45 || true
    echo '=== LAST 22 LOG LINES ==='
    tail -n 22 "$LOGFILE"
  fi
  if [[ -s "$PASS" ]]; then
    echo 'RESULT: MODERATE RESUME QA MARKERS PASS; scientific reference comparison still required'
    cat "$PASS"
  else
    echo 'RESULT: NOT YET VALIDATED. Do not interpret COMPLETED alone as QA PASS.'
  fi
  echo "Isolation: $RUN"
  echo "D8 conversion QA: $REPORT"
}

case "${1:-}" in
  check) check ;;
  submit) submit ;;
  status) status ;;
  *) echo "Usage: bash ${0##*/} check|submit|status" >&2; exit 2 ;;
esac
