#!/usr/bin/env bash
# Read-only scientific diagnostic for MaaltaMerelle MODERATE 02D.4 discrepancy.
# No modifications to hydrology outputs or the pinned GitHub checkout.
set -euo pipefail

ROOT=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
RUN="$ROOT/hydro_01_02/moderate_resume_20261014_v2/run/02_baseline"
INPUT="$ROOT/inputs/E0510000_N7620000/ranta10_lake_id.tif"
AUDIT="$ROOT/hydro_01_02/moderate_02d4_audit_20261014"
JOBFILE="$AUDIT/job_id.txt"

precheck() {
  local f
  for f in \
    "$RUN/routing_surface_land_water_FLT8S.tif" \
    "$RUN/routing_surface_water_storage_FLT8S.tif" \
    "$RUN/02D_lake_depression_component_summary.csv" \
    "$RUN/02D_spill_group_diagnostic.csv" \
    "$INPUT"; do
    if [[ ! -s "$f" ]]; then
      echo "MISSING_INPUT: $f" >&2
      exit 1
    fi
  done
  echo 'PRECHECK_PASS: diagnostic inputs available; existing outputs read-only'
}

submit() {
  precheck
  mkdir -p "$AUDIT"
  if [[ -s "$JOBFILE" ]]; then
    echo "ALREADY_SUBMITTED: $(cat "$JOBFILE")"
    echo 'Use status; this script prevents duplicate submissions.'
    exit 0
  fi

  cat > "$AUDIT/check.R" <<'RSCRIPT'
suppressPackageStartupMessages(library(terra))
root <- Sys.getenv('AUDIT_RUN')
input <- Sys.getenv('AUDIT_LAKE_ID')
out <- Sys.getenv('AUDIT_OUT')
stopifnot(nzchar(root), nzchar(input), nzchar(out))
w <- rast(file.path(root, 'routing_surface_land_water_FLT8S.tif'))
s <- rast(file.path(root, 'routing_surface_water_storage_FLT8S.tif'))
l <- rast(input)
stopifnot(nlyr(w)==1L, nlyr(s)==1L, nlyr(l)==1L,
          compareGeom(w,s,stopOnError=FALSE), compareGeom(w,l,stopOnError=FALSE))
dep <- read.csv(file.path(root,'02D_lake_depression_component_summary.csv'),
                stringsAsFactors=FALSE)
spill <- read.csv(file.path(root,'02D_spill_group_diagnostic.csv'),
                  stringsAsFactors=FALSE)
stopifnot(!anyDuplicated(dep$lake_objectid), !anyDuplicated(spill$lake_objectid),
          setequal(dep$lake_objectid,spill$lake_objectid),
          all(c('spill_raised','n_raised_lake_cells','depression_status') %in% names(dep)))
ids <- as.numeric(dep$lake_objectid)
lake_counts <- numeric(length(ids))
lake_raised_counts <- numeric(length(ids))
valid_cells <- 0
na_mismatch <- 0
positive_cells <- 0
negative_cells <- 0
nearzero_cells <- 0
positive_lake <- 0
positive_land <- 0
min_delta <- Inf
max_delta <- -Inf
max_positive <- 0
min_negative <- 0
tol <- 1e-7
readStart(w); readStart(s); readStart(l)
block_size <- 200L
for (row in seq.int(1L,nrow(w),by=block_size)) {
  nr <- min(block_size,nrow(w)-row+1L)
  x <- readValues(w,row=row,nrows=nr,mat=FALSE)
  y <- readValues(s,row=row,nrows=nr,mat=FALSE)
  id <- readValues(l,row=row,nrows=nr,mat=FALSE)
  stopifnot(length(x)==nr*ncol(w),length(y)==length(x),length(id)==length(x))
  finite <- is.finite(x) & is.finite(y)
  valid_cells <- valid_cells + sum(finite)
  na_mismatch <- na_mismatch + sum(is.na(x)!=is.na(y))
  d <- y[finite] - x[finite]
  positive_cells <- positive_cells + sum(d>tol)
  negative_cells <- negative_cells + sum(d< -tol)
  nearzero_cells <- nearzero_cells + sum(abs(d)<=tol)
  if (length(d)) {
    min_delta <- min(min_delta,min(d))
    max_delta <- max(max_delta,max(d))
    if (any(d>tol)) max_positive <- max(max_positive,max(d[d>tol]))
    if (any(d< -tol)) min_negative <- min(min_negative,min(d[d< -tol]))
  }
  is_lake <- finite & is.finite(id)
  is_raised <- finite & (y-x>tol)
  positive_lake <- positive_lake + sum(is_raised & is_lake)
  positive_land <- positive_land + sum(is_raised & !is_lake)
  lake_counts <- lake_counts + tabulate(match(id[is_lake],ids),nbins=length(ids))
  lake_raised_counts <- lake_raised_counts + tabulate(match(id[is_lake & is_raised],ids),nbins=length(ids))
  cat(sprintf('ROWS_VERIFIED %d-%d\n',row,row+nr-1L))
  flush.console()
}
readStop(w); readStop(s); readStop(l)
dep$audited_lake_cells <- lake_counts
dep$audited_raised_cells <- lake_raised_counts
dep$audited_raised_fraction <- ifelse(lake_counts>0,lake_raised_counts/lake_counts,NA_real_)
dep$raised_count_agrees_with_02d4 <- dep$audited_raised_cells==dep$n_raised_lake_cells
summary <- data.frame(
  metric=c('total_cells','valid_surface_pair_cells','surface_na_mask_mismatches',
           'raised_cells_all','lowered_cells_all','unchanged_within_1e_7_cells',
           'raised_cells_on_lake','raised_cells_off_lake',
           'min_storage_minus_routing_m','max_storage_minus_routing_m',
           'positive_delta_max_m','negative_delta_min_m',
           'lakes_total','spill_raised_lakes',
           'spill_raised_lakes_with_zero_raised_cells',
           'lake_raise_count_disagreements_with_02d4'),
  value=as.character(c(ncell(w),valid_cells,na_mismatch,
                       positive_cells,negative_cells,nearzero_cells,
                       positive_lake,positive_land,
                       min_delta,max_delta,max_positive,min_negative,
                       nrow(dep),sum(dep$spill_raised),
                       sum(dep$spill_raised & dep$audited_raised_cells==0),
                       sum(!dep$raised_count_agrees_with_02d4)))
)
write.csv(summary,file.path(out,'summary.csv'),row.names=FALSE)
write.csv(dep,file.path(out,'lake_audit.csv'),row.names=FALSE)
cat('=== STORAGE / ROUTING SURFACE AUDIT ===\n')
print(summary,row.names=FALSE)
cat('=== SPILL-RAISED LAKES WITH NO RAISED CELLS: LARGEST 15 ===\n')
exceptions <- dep[dep$spill_raised & dep$audited_raised_cells==0, , drop=FALSE]
exceptions <- exceptions[order(exceptions$spill_raise_m,decreasing=TRUE),,drop=FALSE]
keep <- intersect(c('lake_objectid','spill_raise_m','max_storage_raise_m',
                    'audited_lake_cells','audited_raised_cells','depression_status'),names(exceptions))
print(head(exceptions[,keep,drop=FALSE],15),row.names=FALSE)
cat('AUDIT_COMPLETED_READ_ONLY\n')
RSCRIPT

  cat > "$AUDIT/job.sbatch" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_02d4_audit
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --time=00:20:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_02d4_audit_20261014/audit_%j.log
set -euo pipefail
module load r-env/461
export AUDIT_RUN=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_resume_20261014_v2/run/02_baseline
export AUDIT_LAKE_ID=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/inputs/E0510000_N7620000/ranta10_lake_id.tif
export AUDIT_OUT=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/moderate_02d4_audit_20261014
printf 'AUDIT_JOB_START %s host=%s job=%s\n' "$(date -u +%FT%TZ)" "$(hostname)" "$SLURM_JOB_ID"
Rscript --vanilla "$AUDIT_OUT/check.R"
SBATCH
  local jid
  jid=$(sbatch --parsable "$AUDIT/job.sbatch")
  printf '%s\n' "$jid" > "$JOBFILE"
  echo "SUBMITTED_02D4_AUDIT=$jid"
  echo "Results: $AUDIT/summary.csv and $AUDIT/lake_audit.csv"
  echo 'Check: bash "$HOME/maaltamerelle_roihu_moderate_02d4_audit.sh" status'
}

status() {
  if [[ ! -s "$JOBFILE" ]]; then
    echo 'NO_JOB_SUBMITTED; use submit first.'
    exit 1
  fi
  local jid
  jid=$(cat "$JOBFILE")
  sacct -j "$jid" -X --format=JobID,State,Elapsed,ExitCode,MaxRSS || true
  if [[ -f "$AUDIT/summary.csv" ]]; then
    echo '=== COMPLETE SUMMARY ==='
    cat "$AUDIT/summary.csv"
  fi
  echo '=== LAST 35 LOG LINES ==='
  if [[ -f "$AUDIT/audit_${jid}.log" ]]; then
    tail -n 35 "$AUDIT/audit_${jid}.log"
  else
    echo 'No log yet.'
  fi
}
case "${1:-}" in
  submit) submit ;;
  status) status ;;
  check) precheck ;;
  *) echo "Usage: bash \"$0\" {check|submit|status}" >&2; exit 2 ;;
esac
