#!/usr/bin/env bash
#SBATCH --job-name=mm_mod_49_review
#SBATCH --account=project_2004707
#SBATCH --partition=small
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=00:30:00

# One read-only, bounded diagnostic job; never submits nested Slurm jobs.
# Submit only from a private, exact-commit detached checkout in project scratch.
# Results and Slurm stdout/err belong to the caller's private scratch run dir.
set -euo pipefail
umask 077

status=FAILED
finish() {
  rc=$?
  trap - EXIT
  if (( rc == 0 )); then status=TECHNICAL_RUN_COMPLETE; fi
  printf 'BATCH_STATUS=%s EXIT_CODE=%s\n' "$status" "$rc"
  printf 'BATCH_REPORT_PARENT=%s\n' "${MM_REPORT_PARENT:-NOT_SET}"
  printf 'SCIENTIFIC_STATUS=REVIEW_REQUIRED NATIONAL=LOCKED\n'
}
trap finish EXIT

# No dependence on BASH_SOURCE: sbatch executes a spooled script copy.
[[ "${SLURM_JOB_ID:-}" =~ ^[1-9][0-9]{0,19}$ ]] || {
  echo 'STOP: numeric SLURM_JOB_ID required; never execute on login node' >&2; exit 2;
}
[[ "${MM_EXPECTED_COMMIT:-}" =~ ^[0-9a-f]{40}$ ]] || {
  echo 'STOP: exact 40-character review commit required' >&2; exit 2;
}
[[ "${MM_CODE_DIR:-}" == /scratch/project_2004707/pienvedet/mm_mod_probe.*/code ]] || {
  echo 'STOP: private project-scratch checkout required' >&2; exit 2;
}
[[ "${MM_REPORT_PARENT:-}" == "${MM_CODE_DIR%/code}/reports" ]] || {
  echo 'STOP: output must be outside checkout, in the matching scratch run' >&2; exit 2;
}
[[ -d "$MM_CODE_DIR/.git" && -d "$MM_REPORT_PARENT" && ! -L "$MM_CODE_DIR" && ! -L "$MM_REPORT_PARENT" ]] || {
  echo 'STOP: missing or symbolic-link scratch checkout/report directory' >&2; exit 2;
}
[[ "$(stat -c '%u' -- "$MM_REPORT_PARENT")" == "$(id -u)" ]] || {
  echo 'STOP: report parent owner mismatch' >&2; exit 2;
}
# Roihu project scratch inherits setgid (2700) even with umask 077.
# Admit ONLY owner-rwx modes: 0700 or 2700. The setgid bit grants no
# directory traversal/read/write permission to group or others.
mm_private_report_mode() {
  case "$1" in
    700|2700) return 0 ;;
    *) return 1 ;;
  esac
}
mm_private_report_mode "$(stat -c '%a' -- "$MM_REPORT_PARENT")" || {
  echo 'STOP: report parent must be owner-only mode 0700 or 2700' >&2; exit 2;
}
[[ "$(git -C "$MM_CODE_DIR" rev-parse --show-toplevel)" == "$MM_CODE_DIR" &&
   "$(git -C "$MM_CODE_DIR" rev-parse HEAD)" == "$MM_EXPECTED_COMMIT" &&
   -z "$(git -C "$MM_CODE_DIR" status --porcelain --untracked-files=all)" ]] || {
  echo 'STOP: exact clean Git checkout required' >&2; exit 2;
}
[[ "${SLURM_JOB_ACCOUNT:-project_2004707}" == project_2004707 &&
   "${SLURM_JOB_PARTITION:-small}" == small ]] || {
  echo 'STOP: unexpected Slurm account or partition' >&2; exit 2;
}
[[ "$(hostname)" != *login* ]] || {
  echo 'STOP: refused on login node' >&2; exit 2;
}
command -v timeout >/dev/null && command -v scontrol >/dev/null &&
  command -v python3 >/dev/null && command -v git >/dev/null || {
    echo 'STOP: missing host preflight tools' >&2; exit 2;
  }

cd -- "$MM_CODE_DIR"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export R_WHITEBOX_MAX_PROCS=1
export R_ENVIRON_USER=/dev/null R_PROFILE_USER=/dev/null
export GDAL_PAM_ENABLED=NO GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR

printf 'JOB_ID=%s\nCOMMIT=%s\n' "$SLURM_JOB_ID" "$MM_EXPECTED_COMMIT"
printf 'PHASE=ALLOCATION_AND_MEMORY_PREFLIGHT\n'
# This invocation never opens hydrology inputs and cannot initiate R.
timeout --signal=TERM --kill-after=5s 150s \
  bash scripts/roihu_probe_rstudio.sh \
    --expected-commit "$MM_EXPECTED_COMMIT" \
    --output-parent "$MM_REPORT_PARENT" --memory-preflight-only

printf 'PHASE=R_TERRA_ENVIRONMENT\n'
# The documented Roihu module supplies Rscript; use no login-node R jobs.
command -v module >/dev/null || { echo 'STOP: environment modules unavailable' >&2; exit 2; }
module load r-env/461
if [[ -d /projappl/project_2004707/project_rpackages_461 ]]; then
  export R_LIBS=/projappl/project_2004707/project_rpackages_461
fi
command -v Rscript >/dev/null || { echo 'STOP: Rscript unavailable after module load' >&2; exit 2; }
timeout --signal=TERM --kill-after=5s 90s Rscript --vanilla -e '
  if (!requireNamespace("terra", quietly=TRUE)) stop("terra package unavailable")
  cat("R_TERRA_READY R=", as.character(getRversion()),
      " terra=", as.character(packageVersion("terra")), "\n", sep="")
'

printf 'PHASE=BOUNDED_49_LAKE_READONLY_PROBE\n'
# Existing probe enforces: two SHA256 input pins, 49 targets, <=250000 cells
# per window, <=4000000 total cells, <=2000 visits/lake, 2 GiB R-process
# address-space cap and explicit fail-closed memory rechecks. NO Whitebox fill.
timeout --signal=TERM --kill-after=5s 1080s \
  bash scripts/roihu_probe_rstudio.sh \
    --expected-commit "$MM_EXPECTED_COMMIT" \
    --output-parent "$MM_REPORT_PARENT"

printf 'PHASE=FINISHED\n'
printf 'HYDROLOGICAL_APPROVAL=false\n'
