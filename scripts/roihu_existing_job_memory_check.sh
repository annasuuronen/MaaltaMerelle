#!/usr/bin/env bash
# Start from CSC Login node shell. Attach a memory-only step to an EXISTING job.
# No new allocation, R invocation, hydrology input reads or lake probe.
set -euo pipefail
if [[ $# != 3 || ! "$1" =~ ^[1-9][0-9]{0,19}$ || ! "$2" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Expected: JOB_ID EXACT_COMMIT EXISTING_PRIVATE_REPORT_PARENT' >&2
  exit 2
fi
MM_JOB=$1
MM_PIN=$2
MM_OUT=$3
CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ "$(git -C "$CODE" rev-parse HEAD)" != "$MM_PIN" || -n "$(git -C "$CODE" status --porcelain --untracked-files=all)" ]]; then
  echo 'STOP: exact clean checkout required before attaching to a job' >&2
  exit 2
fi
command -v srun >/dev/null || { echo 'STOP: use CSC Login node shell; srun is unavailable here' >&2; exit 2; }
command -v timeout >/dev/null || { echo 'STOP: timeout is required to bound the host preflight' >&2; exit 2; }
# This documented operation creates only a step inside MM_JOB. Slurm enforces
# ownership and existence; Python independently verifies UID/state/node/memory.
exec timeout --signal=TERM --kill-after=5s 60s \
  srun --jobid="$MM_JOB" --overlap --ntasks=1 --cpus-per-task=1 --pty \
  bash -l "$CODE/scripts/roihu_probe_rstudio.sh" --expected-commit "$MM_PIN" \
  --output-parent "$MM_OUT" --memory-preflight-only
