#!/usr/bin/env bash
# Run in an already allocated RStudio COMPUTE session. Never submits a job.
set -euo pipefail
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
exec python3 -I -B "$CODE/scripts/roihu_probe_bundle.py" "$@"
