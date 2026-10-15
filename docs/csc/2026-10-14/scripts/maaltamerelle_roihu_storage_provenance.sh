#!/usr/bin/env bash
# MaaltaMerelle: read-only LOW vs MODERATE 02A storage provenance audit.
# Nothing is submitted until the user explicitly runs `submit` on Roihu.
# Usage: bash ~/maaltamerelle_roihu_storage_provenance.sh check|submit|status
set -euo pipefail
BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
HYDRO="$BASE/hydro_01_02"
CODE=/projappl/project_2004707/MaaltaMerelle
COMMIT=4bbf22bb39181c8a4c27ebc3e2769766043115b8
WBT=/projappl/project_2004707/whitebox/WBT/whitebox_tools
WBT_SHA=96bb47a9d1f0fe8a3cb46df524242c990eab9bc2ae1930e540e09328331172e4
OUT="$HYDRO/storage_provenance_20261014"
JOBFILE="$OUT/jobid"
fail() { echo "STOP: $*" >&2; exit 1; }
check() {
  [[ -d "$CODE/.git" ]] || fail "Git checkout not found: $CODE"
  [[ "$(git -C "$CODE" rev-parse HEAD)" == "$COMMIT" ]] || fail 'Source commit differs from CSC validated pin'
  [[ -z "$(git -C "$CODE" status --porcelain --untracked-files=no)" ]] || fail 'Tracked project source has local edits; stop and inspect'
  [[ -x "$WBT" ]] || fail "WhiteboxTools not found: $WBT"
  printf '%s  %s\n' "$WBT_SHA" "$WBT" | sha256sum -c - || fail 'WhiteboxTools executable changed'
  for id in E200000_N6900000 E0510000_N7620000; do
    d="$HYDRO/runs/$id/02_baseline"
    for file in land_dem_raw_FLT8S.tif land_dem_filled_FLT8S.tif routing_surface_land_water_FLT8S.tif routing_surface_water_storage_FLT8S.tif; do
      [[ -s "$d/$file" ]] || fail "Missing $d/$file"
    done
    [[ -s "$BASE/inputs/$id/ranta10_lake_id.tif" ]] || fail "Missing lake ID raster: $id"
  done
  echo 'PRECHECK_PASS: code pin, Whitebox binary, LOW/MODERATE 02A files all present'
  echo 'This is a read-only audit. It DOES NOT rerun FillDepressions or stage 02.'
}
submit() {
  check
  command -v sbatch >/dev/null || fail 'sbatch unavailable; open Roihu login shell'
  if [[ -e "$OUT" ]]; then
    if [[ -s "$JOBFILE" ]]; then
      echo "ALREADY_SUBMITTED=$(cat "$JOBFILE")"
      echo 'Use status. No duplicate submission.'
    else
      fail "Destination exists with no job ID: $OUT; inspect manually"
    fi
    return 0
  fi
  mkdir -p "$OUT"
  cat > "$OUT/compare.R" <<'RSCRIPT'
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
hydro <- args[1]; out <- args[2]
records <- list()
add <- function(area, comparison, metric, value) {
  records[[length(records) + 1L]] <<- data.frame(area=area, comparison=comparison,
     metric=metric,value=format(value,scientific=FALSE,trim=TRUE),stringsAsFactors=FALSE)
}
compare_pair <- function(area, label, file_a, file_b) {
  a <- rast(file_a); b <- rast(file_b)
  stopifnot(nlyr(a)==1L, nlyr(b)==1L, ncell(a)==36000000,
            compareGeom(a,b,stopOnError=FALSE))
  total <- 0; finite <- 0; na_disagree <- 0; increased <- 0; decreased <- 0; same <- 0
  delta_min <- Inf; delta_max <- -Inf; max_abs <- 0
  readStart(a); readStart(b)
  for (row in seq.int(1L, nrow(a), by=200L)) {
    nr <- min(200L,nrow(a)-row+1L)
    x <- as.numeric(readValues(a,row=row,nrows=nr,mat=FALSE))
    y <- as.numeric(readValues(b,row=row,nrows=nr,mat=FALSE))
    stopifnot(length(x)==nr*ncol(a),length(y)==length(x))
    total <- total + length(x)
    na_disagree <- na_disagree + sum(xor(is.na(x),is.na(y)))
    mask <- is.finite(x) & is.finite(y)
    finite <- finite + sum(mask)
    if (any(mask)) {
      d <- y[mask]-x[mask]
      increased <- increased + sum(d>1e-7)
      decreased <- decreased + sum(d< -1e-7)
      same <- same + sum(abs(d)<=1e-7)
      delta_min <- min(delta_min,min(d))
      delta_max <- max(delta_max,max(d))
      max_abs <- max(max_abs,max(abs(d)))
    }
  }
  readStop(a); readStop(b)
  for (nm in c('total','finite','na_disagree','increased','decreased','same',
               'delta_min','delta_max','max_abs')) {
    add(area,label,nm,get(nm))
  }
  cat(sprintf('PAIR_RESULT %s %s: raised=%s lowered=%s unchanged=%s NA_disagree=%s max_delta_m=%.9f\n',
    area,label,increased,decreased,same,na_disagree,delta_max))
}
for (entry in list(list('LOW','E200000_N6900000'),list('MODERATE','E0510000_N7620000'))) {
  area <- entry[[1L]]; id <- entry[[2L]]
  root <- file.path(hydro,'runs',id,'02_baseline')
  path <- function(file) file.path(root,file)
  compare_pair(area,'LAND_RAW_TO_LAND_FILLED',path('land_dem_raw_FLT8S.tif'),path('land_dem_filled_FLT8S.tif'))
  compare_pair(area,'LAND_WATER_TO_WATER_STORAGE',path('routing_surface_land_water_FLT8S.tif'),path('routing_surface_water_storage_FLT8S.tif'))
}
res <- do.call(rbind,records)
write.csv(res,file.path(out,'comparisons.csv'),row.names=FALSE)
cat('LOW_MODERATE_STORAGE_AUDIT_COMPLETED_READ_ONLY\n')
cat('Not a scientific equivalence validation or a FillDepressions rerun.\n')
RSCRIPT
  cat > "$OUT/job.sbatch" <<'SBATCH'
#!/usr/bin/env bash
#SBATCH --job-name=mm_storage_audit
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=12G
#SBATCH --time=00:20:00
#SBATCH --output=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/storage_provenance_20261014/audit_%j.log
set -euo pipefail
BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b
HYDRO="$BASE/hydro_01_02"
OUT="$HYDRO/storage_provenance_20261014"
echo "START $(date -u +%FT%TZ) node=$(hostname) job=${SLURM_JOB_ID}"
module load r-env/461
export R_LIBS=/projappl/project_2004707/project_rpackages_461
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
Rscript --vanilla "$OUT/compare.R" "$HYDRO" "$OUT"
echo '=== SOURCE AND OUTPUT PROVENANCE ==='
printf 'R: '; Rscript --vanilla -e 'cat(R.version.string, " terra ", as.character(packageVersion("terra")), "\n", sep="")'
for id in E200000_N6900000 E0510000_N7620000; do
  d="$HYDRO/runs/$id/02_baseline"
  echo "=== $id ==="
  for f in land_dem_raw_FLT8S.tif land_dem_filled_FLT8S.tif routing_surface_land_water_FLT8S.tif routing_surface_water_storage_FLT8S.tif; do
    stat -c '%y | %s bytes | %n' "$d/$f"
    sha256sum "$d/$f"
    if command -v gdalinfo >/dev/null 2>&1; then
      gdalinfo -mdd all "$d/$f" > "$OUT/${id}_${f%.tif}_gdalinfo.txt"
      echo "GDAL_METADATA_FILE=$OUT/${id}_${f%.tif}_gdalinfo.txt"
    fi
  done
done
if ! command -v gdalinfo >/dev/null 2>&1; then
  echo 'gdalinfo not installed; TIFF provenance was recorded via stat and SHA256 only.'
fi
echo "AUDIT_PASS_READ_ONLY $(date -u +%FT%TZ)"
SBATCH
  bash -n "$OUT/job.sbatch" || fail 'Generated batch failed syntax check'
  jid=$(sbatch --parsable "$OUT/job.sbatch")
  jid=${jid%%;*}
  echo "$jid" > "$JOBFILE"
  echo "SUBMITTED_STORAGE_AUDIT=$jid"
  echo "READ_ONLY_OUTPUT=$OUT"
  echo "Check: bash '$0' status"
}
status() {
  [[ -s "$JOBFILE" ]] || fail 'No submitted job; run submit when ready'
  jid=$(cat "$JOBFILE")
  echo "=== LOW/MODERATE STORAGE PROVENANCE $jid ==="
  sacct -j "$jid" -X --format=JobID,State,Elapsed,ExitCode,MaxRSS || true
  squeue -j "$jid" -o '%.18i %.10T %.10M %.30R' 2>/dev/null || true
  if [[ -s "$OUT/comparisons.csv" ]]; then
    echo '=== COMPARISON SUMMARY (RAISED / LOWERED CELLS) ==='
    python3 - "$OUT/comparisons.csv" <<'PY'
import csv,sys
r=list(csv.DictReader(open(sys.argv[1],newline='')))
for area in ('LOW','MODERATE'):
    for cmp in ('LAND_RAW_TO_LAND_FILLED','LAND_WATER_TO_WATER_STORAGE'):
        a={x['metric']:x['value'] for x in r if x['area']==area and x['comparison']==cmp}
        print(f"{area} {cmp}: raised={a.get('increased','?')} lowered={a.get('decreased','?')} unchanged={a.get('same','?')} NA_mismatch={a.get('na_disagree','?')} max_delta_m={a.get('delta_max','?')}")
PY
  fi
  if [[ -f "$OUT/audit_${jid}.log" ]]; then
    echo '=== LAST LOG LINES ==='
    tail -n 30 "$OUT/audit_${jid}.log"
  fi
  echo 'No original rasters or Github source are modified by this job.'
}
case "${1:-}" in
  check) check ;;
  submit) submit ;;
  status) status ;;
  *) echo "Usage: bash '$0' check|submit|status" >&2; exit 2 ;;
esac
