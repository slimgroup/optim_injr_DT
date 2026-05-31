#!/usr/bin/env bash
# Script to submit missing POF samples using optim_inject_7cases_fix.jl
# Missing samples:
#   - POF eps=0.01, sample 18
#   - POF eps=0.05, sample 64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# POF base arguments
POF_BASE="--use_pof --pof_as_constraint --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime"

echo "=========================================="
echo "Submitting Missing POF Samples (using fix version)"
echo "=========================================="
echo ""

# Function to submit a single sample using fix version
submit_one_sample() {
  local TAG="$1"
  local EPS="$2"
  local SAMPLE="$3"
  local jobname="${TAG}_s${SAMPLE}_fix"
  
  echo "[SUBMIT] ${TAG} sample=${SAMPLE} (using optim_inject_7cases_fix.jl)"
  
  # Submit the job directly with julia command (not using optim_inject_pace.sh)
  JOBLINE=$(sbatch --parsable --array="${SAMPLE}" --chdir="${ROOT_DIR}" \
            --job-name="${jobname}" \
            --account=gts-fherrmann9 \
            -N 1 --ntasks-per-node=1 --cpus-per-task=1 --mem=64G \
            -t 24:00:00 -q inferno \
            --output="${ROOT_DIR}/logs/out_${jobname}_%A_%a.txt" \
            --error="${ROOT_DIR}/logs/err_${jobname}_%A_%a.txt" \
            --signal=TERM@60 \
            --mail-type=BEGIN,END,FAIL \
            --mail-user=hli853@gatech.edu \
            --wrap="module purge && module load julia/1.11.3 2>/dev/null || true && \
                    export JULIA_DEPOT_PATH=\$HOME/julia-depot && mkdir -p \$JULIA_DEPOT_PATH && \
                    export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python && \
                    export JULIA_PKG_PRECOMPILE_AUTO=0 && export MPLBACKEND=Agg && \
                    export OPENBLAS_NUM_THREADS=1 && export OMP_NUM_THREADS=1 && \
                    cd ${ROOT_DIR} && \
                    julia --project=. -t 1 src/archive/optim_inject_7cases_fix.jl \
                    --idx_num \${SLURM_ARRAY_TASK_ID} \
                    --niterations 40 --inj_guess 0.20 \
                    --save_plots --plot_stride 5 --save_every 5 --grad_forward \
                    ${POF_BASE} --eps_pof ${EPS}" 2>&1)
  
  if [ $? -eq 0 ]; then
    JOBID="${JOBLINE%%_*}"
    echo "  -> Job submitted: ${JOBID}"
    return 0
  else
    echo "  -> ERROR: ${JOBLINE}"
    return 1
  fi
}

# Submit missing samples
echo "1. Submitting POF eps=0.01, sample 18..."
submit_one_sample "DT_POF_eps=0.01" "0.01" "18"

echo ""
echo "2. Submitting POF eps=0.05, sample 64..."
submit_one_sample "DT_POF_eps=0.05" "0.05" "64"

echo ""
echo "=========================================="
echo "Submission complete!"
echo "=========================================="
echo ""
echo "You can check job status with:"
echo "  squeue -u \$USER"
echo ""
echo "Check logs in: ${ROOT_DIR}/logs/"

