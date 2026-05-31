#!/bin/bash
#SBATCH --job-name=thresh_sens
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 12:00:00
#SBATCH -q inferno
#SBATCH --output=logs/threshold_sensitivity_%j.txt
#SBATCH --error=logs/threshold_sensitivity_%j.txt
#SBATCH --signal=TERM@60
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

# Generic threshold sensitivity analysis script
# Supports POF-only, CVaR-only, or both (POF+CVaR)
# 
# Usage examples:
#   # Basic run with defaults (POF+CVaR, 5 thresholds, 10 iterations)
#   sbatch --array=1-5 scripts/shell/submit/submit_threshold_sensitivity.sh
#   
#   # POF-only mode
#   export USE_POF=1 USE_CVAR=0
#   sbatch --array=1-5 scripts/shell/submit/submit_threshold_sensitivity.sh
#   
#   # CVaR-only mode (requires gamma table)
#   export USE_POF=0 USE_CVAR=1 GAMMA_TABLE_PATH=path/to/gamma_table.jld2
#   sbatch --array=1-5 scripts/shell/submit/submit_threshold_sensitivity.sh
#   
#   # Custom thresholds and iterations
#   export THRESHOLD_VALUES=2.0,3.0,4.0 NITERATIONS=20
#   sbatch --array=1-3 scripts/shell/submit/submit_threshold_sensitivity.sh

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

# Configuration (with defaults)
IDX_NUM="${IDX_NUM:-128}"
USE_POF="${USE_POF:-1}"
USE_CVAR="${USE_CVAR:-1}"
EPS_POF="${EPS_POF:-0.01}"
LAMBDA_POF="${LAMBDA_POF:-1.0}"
LAMBDA_CVAR="${LAMBDA_CVAR:-1.0}"
NITERATIONS="${NITERATIONS:-10}"
THRESHOLD_MIN="${THRESHOLD_MIN:-2.0}"
THRESHOLD_MAX="${THRESHOLD_MAX:-6.0}"
THRESHOLD_NUM="${THRESHOLD_NUM:-5}"
GAMMA_TABLE_PATH="${GAMMA_TABLE_PATH:-}"

# Threshold list handling (supports SLURM array splitting)
THRESHOLD_VALUES="${THRESHOLD_VALUES:-}"
if [[ -z "$THRESHOLD_VALUES" ]]; then
    # Generate threshold list from min/max/num
    THRESHOLD_VALUES=$(python3 -c "import numpy as np; print(','.join([f'{x:.6f}' for x in np.linspace($THRESHOLD_MIN, $THRESHOLD_MAX, $THRESHOLD_NUM)]))")
fi

THRESHOLD_VALUES="${THRESHOLD_VALUES//[$'\t\r\n ']/}"
IFS=',' read -r -a THRESH_ARRAY <<< "$THRESHOLD_VALUES"
THRESH_COUNT="${#THRESH_ARRAY[@]}"

if [[ "${THRESH_COUNT}" -eq 0 ]]; then
  echo "[ERROR] THRESHOLD_VALUES is empty" >&2
  exit 1
fi

if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  TASK_ID="${SLURM_ARRAY_TASK_ID}"
  if (( TASK_ID < 1 || TASK_ID > THRESH_COUNT )); then
    echo "[ERROR] SLURM_ARRAY_TASK_ID=${TASK_ID} outside valid range 1-${THRESH_COUNT}" >&2
    exit 2
  fi
  SELECTED_THRESHOLD="${THRESH_ARRAY[$((TASK_ID-1))]}"
  echo "Split run: task ${TASK_ID}/${SLURM_ARRAY_TASK_MAX:-$THRESH_COUNT} -> threshold=${SELECTED_THRESHOLD} MPa"
  THRESH_ARGS=(--threshold_list "${SELECTED_THRESHOLD}" --split_threshold_jobs --split_job_index "${TASK_ID}" --split_job_total "${THRESH_COUNT}" --merge_results)
else
  echo "Running all thresholds in a single job: ${THRESHOLD_VALUES}"
  THRESH_ARGS=(--threshold_list "${THRESHOLD_VALUES}")
fi

trap 'echo "[WARN] SIGTERM received; try to save…"' TERM

cd "$SLURM_SUBMIT_DIR"

echo "Job started at $(date)"
echo "Configuration:"
echo "  Sample: $IDX_NUM"
echo "  Use POF: $USE_POF"
echo "  Use CVaR: $USE_CVAR"
echo "  Eps POF: $EPS_POF"
echo "  Iterations: $NITERATIONS"
echo "  Thresholds: $THRESHOLD_VALUES"
echo ""

# Build Julia command arguments
JULIA_ARGS=(
  --idx_num "$IDX_NUM"
  --niterations "$NITERATIONS"
  --grad_forward
  "${THRESH_ARGS[@]}"
)

# Add POF arguments if enabled
if [[ "$USE_POF" == "1" ]]; then
  JULIA_ARGS+=(--use_pof --eps_pof "$EPS_POF" --lambda_pof "$LAMBDA_POF")
fi

# Add CVaR arguments if enabled
if [[ "$USE_CVAR" == "1" ]]; then
  # Auto-find gamma table if not specified
  if [[ -z "$GAMMA_TABLE_PATH" ]]; then
    LATEST_GAMMA=$(ls -t "$SLURM_SUBMIT_DIR/data/DT_control/exp_name=step1/threshold_sensitivity/gamma_table__sample=${IDX_NUM}__"*.jld2 2>/dev/null | head -1)
    if [[ -n "$LATEST_GAMMA" ]]; then
      GAMMA_TABLE_PATH="$LATEST_GAMMA"
      echo "Auto-detected gamma table: $GAMMA_TABLE_PATH"
    else
      echo "[ERROR] CVaR enabled but no gamma table found. Set GAMMA_TABLE_PATH or generate one first." >&2
      exit 1
    fi
  fi
  
  # Resolve absolute path if relative
  if [[ ! "$GAMMA_TABLE_PATH" =~ ^/ ]]; then
    GAMMA_TABLE_PATH="$SLURM_SUBMIT_DIR/$GAMMA_TABLE_PATH"
  fi
  
  if [[ ! -f "$GAMMA_TABLE_PATH" ]]; then
    echo "[ERROR] Gamma table not found: $GAMMA_TABLE_PATH" >&2
    exit 1
  fi
  
  echo "Using gamma table: $GAMMA_TABLE_PATH"
  JULIA_ARGS+=(--use_cvar --lambda_cvar "$LAMBDA_CVAR" --gamma_table_path "$GAMMA_TABLE_PATH" --gamma_table_eps "$EPS_POF")
fi

# Run Julia script
julia --project="$SLURM_SUBMIT_DIR" -t 1 src/threshold_sensitivity.jl "${JULIA_ARGS[@]}"

echo "Job completed at $(date)"
