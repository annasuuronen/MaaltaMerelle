#!/usr/bin/env bash
# MaaltaMerelle 2026-10-14: isolated rerun of ORIGINAL WhiteboxTools
# FillDepressions(dem=routing_surface_land_water, fix_flats=FALSE).
# Does NOT alter baseline, source repository or validated D8 data.
# Usage: bash ~/maaltamerelle_roihu_moderate_fill_recheck.sh check|submit|status
set -euo pipefail

BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
HYDRO="$BASE/hydro_01_02"
ID=E0510000_N7620000
ORIGINAL="$HYDRO/runs/$ID/02_baseline"
LAKE_ID="$BASE/inputs/$ID/ranta10_lake_id.tif"
DEP_SUMMARY="$HYDRO/moderate_resume_20261014_v2/run/02_baseline/02D_lake_depression_component_summary.csv"
WBT=/projappl/project_2004707/whitebox/WBT/whitebox_tools
CODE=/projappl/project_2004707/MaaltaMerelle
COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
WBT_SHA=96bb47a9d1f0fe8a3cb46df524242c990eab9bc2ae1930e540e09328331172e4
DEST="$HYDRO/moderate_fill_recheck_20261014"
JOBFILE="$DEST/slurm_jobid"
RESULT="$DEST/fresh_water_storage.tif"
REPORT="$DEST/summary.csv"
LAKEREPORT="$DEST/lake_summary.csv"

fail() { printf 'PRECHECK FAILED: %s\n' "$*" >&2; exit 1; }

check() {
  [[ -s "$ORIGINAL/routing_surface_land_water_FLT8S.tif" ]] || fail 'Original land-water routing surface missing'
  [[ -s "$ORIGINAL/routing_surface_water_storage_FLT8S.tif" ]] || fail 'Original WATER_STORAGE missing'
  [[ -s "$LAKE_ID" ]] || fail 'Lake-ID raster missing'
  [[ -s "$DEP_SUMMARY" ]] || fail 'Previous 02D.4 lake summary missing'
  [[ -x "$WBT" ]] || fail 'WhiteboxTools executable missing'
  [[ -d "$CODE/.git" ]] || fail 'Pinned Git repository missing'
  [[ "$(git -C "$CODE" rev-parse HEAD)" == "$COMMIT" ]] || fail 'Pinned source commit changed'
  [[ -z "$(git -C "$CODE" status --porcelain --untracked-files=no)" ]] || fail 'Tracked source files have been modified'
  printf '%s  %s\n' "$WBT_SHA" "$WBT" | sha256sum -c - || fail 'WhiteboxTools checksum mismatch'
  echo 'PRECHECK_PASS: unchanged input surfaces, original source commit, same WBT binary as GitHub fixture'
  echo 'The experiment uses FillDepressions with fix_flats=FALSE (no --fix_flats flag).'
  echo 'All NEW outputs will be written only to:' "$DEST"
}

submit() {
  check
  if [[ -e "$DEST" ]]; then
    if [[ -s "$JOBFILE" ]]; then
      echo "ALREADY_SUBMITTED=$(cat "$JOBFILE")"
      echo "Use bash '$0' status; duplicate runs are prevented."
    else
      echo "EXISTING_DESTINATION: $DEST; inspect it manually; will not overwrite anything."
    fi
    return 0
  fi
  mkdir "$DEST"
  cat > "$DEST/compare.R" <<'RSCRIPT'
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==6L)
infile <- args[1]; oldfile <- args[2]; newfile <- args[3]
lakefile <- args[4]; depfile <- args[5]; outputdir <- args[6]
x <- rast(infile); old <- rast(oldfile); new <- rast(newfile); lake <- rast(lakefile)
stopifnot(nlyr(x)==1L,nlyr(old)==1L,nlyr(new)==1L,nlyr(lake)==1L,
          ncell(x)==36000000,
          compareGeom(x,old,stopOnError=FALSE),
          compareGeom(x,new,stopOnError=FALSE),
          compareGeom(x,lake,stopOnError=FALSE))
dep <- read.csv(depfile,stringsAsFactors=FALSE)
stopifnot(all(c('lake_objectid','spill_raised','n_raised_lake_cells') %in% names(dep)),
          !anyDuplicated(dep$lake_objectid))
ids <- as.numeric(dep$lake_objectid)
old_raised <- numeric(length(ids)); new_raised <- numeric(length(ids))
metrics <- c('n_cells','na_mask_disagreement_new_vs_input','na_mask_disagreement_new_vs_old',
             'old_raised_cells_gt_1e_7','new_raised_cells_gt_1e_7',
             'new_lowered_cells_lt_minus_1e_7',
             'new_vs_old_changed_cells_gt_1e_7',
             'new_vs_old_max_abs_difference_m',
             'new_minus_input_min_m','new_minus_input_max_m',
             'new_raised_lake_cells','old_raised_lake_cells')
counter <- setNames(rep(0,length(metrics)),metrics)
counter['n_cells'] <- ncell(x)
counter['new_minus_input_min_m'] <- Inf
counter['new_minus_input_max_m'] <- -Inf
readStart(x); readStart(old); readStart(new); readStart(lake)
for (row in seq.int(1L,nrow(x),by=200L)) {
  nr <- min(200L,nrow(x)-row+1L)
  a <- as.numeric(readValues(x,row=row,nrows=nr,mat=FALSE))
  b <- as.numeric(readValues(old,row=row,nrows=nr,mat=FALSE))
  c <- as.numeric(readValues(new,row=row,nrows=nr,mat=FALSE))
  id <- as.numeric(readValues(lake,row=row,nrows=nr,mat=FALSE))
  stopifnot(length(a)==nr*ncol(x),length(a)==length(b),length(a)==length(c),length(a)==length(id))
  counter['na_mask_disagreement_new_vs_input'] <- counter['na_mask_disagreement_new_vs_input'] + sum(xor(is.na(a),is.na(c)))
  counter['na_mask_disagreement_new_vs_old'] <- counter['na_mask_disagreement_new_vs_old'] + sum(xor(is.na(b),is.na(c)))
  valid <- is.finite(a) & is.finite(b) & is.finite(c)
  if (!any(valid)) next
  da <- c[valid]-a[valid]; db <- b[valid]-a[valid]; dx <- c[valid]-b[valid]
  counter['old_raised_cells_gt_1e_7'] <- counter['old_raised_cells_gt_1e_7'] + sum(db>1e-7)
  counter['new_raised_cells_gt_1e_7'] <- counter['new_raised_cells_gt_1e_7'] + sum(da>1e-7)
  counter['new_lowered_cells_lt_minus_1e_7'] <- counter['new_lowered_cells_lt_minus_1e_7'] + sum(da< -1e-7)
  counter['new_vs_old_changed_cells_gt_1e_7'] <- counter['new_vs_old_changed_cells_gt_1e_7'] + sum(abs(dx)>1e-7)
  counter['new_vs_old_max_abs_difference_m'] <- max(counter['new_vs_old_max_abs_difference_m'],max(abs(dx)))
  counter['new_minus_input_min_m'] <- min(counter['new_minus_input_min_m'],min(da))
  counter['new_minus_input_max_m'] <- max(counter['new_minus_input_max_m'],max(da))
  raised_new <- valid & (c-a>1e-7) & is.finite(id)
  raised_old <- valid & (b-a>1e-7) & is.finite(id)
  counter['new_raised_lake_cells'] <- counter['new_raised_lake_cells'] + sum(raised_new)
  counter['old_raised_lake_cells'] <- counter['old_raised_lake_cells'] + sum(raised_old)
  if (any(raised_new)) new_raised <- new_raised + tabulate(match(id[raised_new],ids),nbins=length(ids))
  if (any(raised_old)) old_raised <- old_raised + tabulate(match(id[raised_old],ids),nbins=length(ids))
  cat(sprintf('COMPARE_ROWS %d-%d\n',row,row+nr-1L))
}
readStop(x);readStop(old);readStop(new);readStop(lake)
summary <- data.frame(metric=names(counter),value=as.numeric(counter))
write.csv(summary,file.path(outputdir,'summary.csv'),row.names=FALSE)
dep$old_raised_lake_cells <- old_raised
dep$fresh_raised_lake_cells <- new_raised
write.csv(dep,file.path(outputdir,'lake_summary.csv'),row.names=FALSE)
cat('=== FRESH FILLDEPRESSIONS / STORED WATER_STORAGE COMPARISON ===\n')
print(summary,row.names=FALSE)
cat('=== SPILL-RAISED LAKES: COUNT WITH NO NEW RAISED CELLS ===\n')
cat(sum(dep$spill_raised & dep$fresh_raised_lake_cells==0), 'of',sum(dep$spill_raised),'\n')
cat('=== LARGEST 12 SPILL-RAISED LAKES ===\n')
q <- dep[dep$spill_raised,,drop=FALSE]
q <- q[order(q$spill_raise_m,decreasing=TRUE),,drop=FALSE]
print(head(q[,intersect(c('lake_objectid','spill_raise_m','old_raised_lake_cells','fresh_raised_lake_cells'),names(q)),drop=FALSE],12),row.names=FALSE)
stopifnot(counter['na_mask_disagreement_new_vs_input']==0,
          counter['na_mask_disagreement_new_vs_old']==0,
          counter['new_lowered_cells_lt_minus_1e_7']==0)
cat('FRESH_FILL_COMPARISON_QA_PASS: geometry, NA masks and no surface lowering; differences reported above.\n')
cat('Scientific agreement with GitHub reference has NOT yet been established.\n')
RSCRIPT

  cat > "$DEST/job.sbatch" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_mod_fill_recheck
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=00:22:00
#SBATCH --nodelist=rc4129
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_fill_recheck_20261014/job_%j.log
set -euo pipefail
BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
HYDRO="$BASE/hydro_01_02"
DIR="$HYDRO/moderate_fill_recheck_20261014"
SOURCE="$HYDRO/runs/E0510000_N7620000/02_baseline"
LAND="$SOURCE/routing_surface_land_water_FLT8S.tif"
OLD="$SOURCE/routing_surface_water_storage_FLT8S.tif"
LAKE="$BASE/inputs/E0510000_N7620000/ranta10_lake_id.tif"
DEP="$HYDRO/moderate_resume_20261014_v2/run/02_baseline/02D_lake_depression_component_summary.csv"
WBT=/projappl/project_2004707/whitebox/WBT/whitebox_tools
NEW="$DIR/fresh_water_storage.tif"

printf 'FILL_RECHECK_START_UTC=%s host=%s job=%s\n' "$(date -u +%FT%TZ)" "$(hostname)" "$SLURM_JOB_ID"
echo 'PINNED METHOD: WhiteboxTools FillDepressions, fix_flats=FALSE, max_procs=1.'
echo 'Whitebox --fix_flats flag is intentionally OMITTED, just as in the original R pipeline.'
echo "READ_ONLY_INPUT=$LAND"
echo "OLD_WATER_STORAGE_READ_ONLY=$OLD"
echo "ISOLATED_FRESH_OUTPUT=$NEW"
[[ ! -e "$NEW" ]] || { echo 'STOP: fresh output exists; refusing overwrite'; exit 1; }
set +e
timeout -k 15s 900s "$WBT" --run=FillDepressions --dem="$LAND" --output="$NEW" --max_procs=1 -v
rc=$?
set -e
echo "WHITEBOX_FILL_EXIT=$rc"
[[ "$rc" == 0 ]] || { echo 'FILL_RECHECK_WHITEBOX_FAILED_OR_TIMED_OUT; no input files changed'; exit "$rc"; }
[[ -s "$NEW" ]] || { echo 'WHITEBOX_FILL_NO_OUTPUT'; exit 1; }
module load r-env/461
export R_LIBS=/projappl/project_2004707/project_rpackages_461
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
Rscript --vanilla "$DIR/compare.R" "$LAND" "$OLD" "$NEW" "$LAKE" "$DEP" "$DIR"
echo "FILL_RECHECK_COMPLETE_UTC=$(date -u +%FT%TZ)"
SBATCH
  bash -n "$DEST/job.sbatch" || fail 'Generated job script failed Bash syntax check'
  local job
  job=$(sbatch --parsable "$DEST/job.sbatch")
  job=${job%%;*}
  printf '%s\n' "$job" > "$JOBFILE"
  echo "SUBMITTED_FILL_RECHECK=$job"
  echo "OUTPUT=$DEST"
  echo "Check: bash '$0' status"
}

status() {
  [[ -s "$JOBFILE" ]] || fail 'No job yet; run submit first'
  local job
  job=$(cat "$JOBFILE")
  echo "=== MODERATE FillDepressions recheck job $job ==="
  sacct -j "$job" -X --format=JobID,State,Elapsed,ExitCode,MaxRSS || true
  squeue -j "$job" -o '%.18i %.10T %.10M %.35R' 2>/dev/null || true
  if [[ -s "$REPORT" ]]; then
    echo '=== FRESH OUTPUT VS EXISTING WATER_STORAGE: ALL CELLS ==='
    cat "$REPORT"
  fi
  echo '=== LAST 30 LOG LINES ==='
  if [[ -f "$DEST/job_${job}.log" ]]; then
    tail -n 30 "$DEST/job_${job}.log"
  else
    echo 'Job log not yet created.'
  fi
  echo 'No original hydrology files or GitHub code are written by this test.'
}
case "${1:-}" in
  check) check ;;
  submit) submit ;;
  status) status ;;
  *) echo "Usage: bash $0 {check|submit|status}" >&2; exit 2 ;;
esac
