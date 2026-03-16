#!/usr/bin/env bash
# Query progress for step-2 dual-prior jobs and show where logs/results live.
# Run from project root:  bash scripts/shell/check_step2_progress.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

# Where SLURM writes stdout/stderr: often project root's logs/ when sbatch runs with cwd=root
PROJECT_LOGS="${ROOT_DIR}/logs"
SUBMIT_LOGS="${ROOT_DIR}/../logs"

echo "=========================================="
echo "Step-2 dual-prior progress"
echo "=========================================="
echo ""

echo "1. Queue (step2 jobs for your user):"
echo "   ---"
squeue -u "$USER" -o "%.10i %.36j %.8T %.10M %.6D %R" 2>/dev/null | head -1
squeue -u "$USER" 2>/dev/null | grep -E "step2|STEP2" || true
echo "   ---"
echo ""

echo "2. Result counts (final.jld2 per case, step2):"
DATA="${ROOT_DIR}/data/DT_control/exp_name=step2"
if [[ -d "${DATA}" ]]; then
  for dir in "${DATA}"/*/; do
    [[ -d "$dir" ]] || continue
    name=$(basename "$dir")
    count=$(find "$dir" -maxdepth 2 -name "final.jld2" 2>/dev/null | wc -l)
    echo "   ${name}: ${count} / 32"
  done
else
  echo "   (no data dir yet: ${DATA})"
fi
echo ""

echo "3. Log locations:"
if [[ -d "${PROJECT_LOGS}" ]]; then
  n=$(ls "${PROJECT_LOGS}"/out_*.txt 2>/dev/null | wc -l)
  echo "   ${PROJECT_LOGS}"
  echo "      -> ${n} out_*.txt files"
  echo "   Latest 3:"
  ls -lt "${PROJECT_LOGS}"/out_*.txt 2>/dev/null | head -3 || true
else
  echo "   ${PROJECT_LOGS} (not found)"
fi
if [[ -d "${SUBMIT_LOGS}" ]] && [[ "${SUBMIT_LOGS}" != "${PROJECT_LOGS}" ]]; then
  n=$(ls "${SUBMIT_LOGS}"/out_*.txt 2>/dev/null | wc -l)
  echo "   Or: ${SUBMIT_LOGS} -> ${n} out_*.txt"
fi
echo ""

echo "4. Useful commands:"
echo "   Watch queue:     squeue -u \$USER"
echo "   Job history:    sacct -u \$USER --format=JobID,JobName%30,State,Elapsed,ExitCode -S \$(date -d '1 day ago' +%Y-%m-%d)"
echo "   Tail one log:   tail -f ${PROJECT_LOGS}/out_<JOBNAME>_<JOBID>_<ARRAYID>.txt"
echo "   List outputs:   ls -lt ${DATA}/<case_tag>/sample=*/final.jld2"
echo "=========================================="
