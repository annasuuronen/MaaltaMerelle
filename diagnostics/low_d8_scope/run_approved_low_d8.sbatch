#!/bin/bash -l
#SBATCH --job-name=mm_low_d8_frac
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=MM_LOW_D8_fraction_%j.log

# Read-only LOW D8 validation; one bounded Slurm job, no raster writes.
set -Eeuo pipefail
umask 077

: "${SLURM_JOB_ID:?STOP: submit with sbatch, never run this as a shell script}"
: "${SLURM_SUBMIT_DIR:?STOP: unknown submission directory}"
cd "$SLURM_SUBMIT_DIR"
[[ -f SHA256SUMS && -f lake_to_land_d8_core.R && \
   -f test_lake_to_land_d8.R && -f scan_entire_low_d8.R ]] || {
  echo 'STOP: diagnostic files are missing' >&2; exit 2;
}
sha256sum --check --status SHA256SUMS || {
  echo 'STOP: source SHA256 verification failed' >&2; exit 2;
}

REPO=/projappl/project_2004707/MaaltaMerelle
BASE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/hydro_01_02/runs/E200000_N6900000/02_baseline
SOURCE=/scratch/project_2004707/pienvedet/csc_validation_4bbf22b/inputs/E200000_N6900000
EXPECTED_ORIGINAL=4bbf22bb39181c8a4c27ebc3e2769766043115b8
[[ -d "$REPO/.git" || -f "$REPO/.git" ]] || { echo 'STOP: canonical repository absent' >&2; exit 2; }
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$EXPECTED_ORIGINAL" ]] || {
  echo 'STOP: canonical CSC checkout is not the validated original commit' >&2; exit 2;
}
for p in "$BASE/d8_pointer_land_water_FLT8S.tif" \
         "$SOURCE/ranta10_water_class.tif" \
         "$SOURCE/ranta10_lake_id.tif"; do
  [[ -f "$p" && ! -L "$p" ]] || { echo "STOP: missing or linked raster: $p" >&2; exit 2; }
done

module load r-env/461
command -v Rscript >/dev/null || { echo 'STOP: no Rscript' >&2; exit 2; }
printf 'JOB_ID: %s\nCSC_ORIGINAL_COMMIT: %s\n' "$SLURM_JOB_ID" "$EXPECTED_ORIGINAL"
printf 'RESOURCE_LIMITS: 1 CPU, 8G, 00:30:00\nMODE: READ_ONLY\n'
printf '========== SYNTHETIC PREFLIGHT ==========\n'
Rscript --vanilla test_lake_to_land_d8.R
printf '========== SINGLE LOW BLOCK SCAN ==========\n'
Rscript --vanilla scan_entire_low_d8.R "$BASE" "$SOURCE"
printf 'PASS: APPROVED LOW D8 READ-ONLY SLURM JOB FINISHED\n'
