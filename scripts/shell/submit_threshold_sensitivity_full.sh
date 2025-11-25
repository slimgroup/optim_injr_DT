#!/bin/bash
#SBATCH --job-name=thresh_sens_full_128
#SBATCH --account=gts-fherrmann9
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH -t 24:00:00
#SBATCH -q inferno
#SBATCH --output=logs/threshold_sensitivity_full_%j.txt
#SBATCH --error=logs/threshold_sensitivity_full_%j.txt
#SBATCH --signal=TERM@60
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=hli853@gatech.edu

# Full run threshold sensitivity analysis (POF + CVaR enabled, using gamma lookup table)
# Estimated runtime: 10-20 hours (10 thresholds, 20 iterations each)
# 
# Usage:
#   # Use default gamma table (eps=0.01)
#   sbatch --array=1-10 scripts/shell/submit_threshold_sensitivity_full.sh
#   
#   # Use custom gamma table and eps
#   export GAMMA_TABLE_PATH=scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2
#   export EPS_POF=0.005
#   sbatch --array=1-10 scripts/shell/submit_threshold_sensitivity_full.sh

set -euo pipefail
module purge
module load julia/1.11.3 2>/dev/null || true

# Fixed environment (PyCall stable, single-threaded plotting)
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
export JULIA_PKG_PRECOMPILE_AUTO=0
export MPLBACKEND=Agg
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
mkdir -p logs

# Threshold list handling (supports SLURM array splitting)
THRESHOLD_VALUES="${THRESHOLD_VALUES:-2.0,2.444444,2.888889,3.333333,3.777778,4.222222,4.666667,5.111111,5.555556,6.0}"
THRESHOLD_VALUES="${THRESHOLD_VALUES//[$'\t\r\n ']/}"
IFS=',' read -r -a THRESH_ARRAY <<< "$THRESHOLD_VALUES"
THRESH_COUNT="${#THRESH_ARRAY[@]}"
if [[ "${THRESH_COUNT}" -eq 0 ]]; then
  echo "[ERROR] THRESHOLD_VALUES is empty. Provide comma-separated list." >&2
  exit 1
fi

if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  TASK_ID="${SLURM_ARRAY_TASK_ID}"
  if (( TASK_ID < 1 || TASK_ID > THRESH_COUNT )); then
    echo "[ERROR] SLURM_ARRAY_TASK_ID=${TASK_ID} outside 1-${THRESH_COUNT}" >&2
    exit 2
  fi
  SELECTED_THRESHOLD="${THRESH_ARRAY[$((TASK_ID-1))]}"
  echo "Split run detected: task ${TASK_ID}/${SLURM_ARRAY_TASK_MAX:-$THRESH_COUNT} -> threshold=${SELECTED_THRESHOLD} MPa"
  THRESH_ARGS=(--threshold_list "${SELECTED_THRESHOLD}" --split_threshold_jobs --split_job_index "${TASK_ID}" --split_job_total "${THRESH_COUNT}" --merge_results)
else
  echo "Running all thresholds in a single job: ${THRESHOLD_VALUES}"
  THRESH_ARGS=(--threshold_list "${THRESHOLD_VALUES}")
fi

trap 'echo "[WARN] SIGTERM received; try to save…"' TERM

# Change to project directory
cd "$SLURM_SUBMIT_DIR"

echo "Job started at $(date)"
echo "Running threshold sensitivity analysis (full mode)"

# Gamma table configuration
GAMMA_TABLE_PATH="${GAMMA_TABLE_PATH:-scripts/gamma_tables/gamma_table__sample=128__20251125_122949.jld2}"
EPS_POF="${EPS_POF:-0.01}"

# Resolve absolute path if relative
if [[ ! "$GAMMA_TABLE_PATH" =~ ^/ ]]; then
  GAMMA_TABLE_PATH="$SLURM_SUBMIT_DIR/$GAMMA_TABLE_PATH"
fi

if [[ ! -f "$GAMMA_TABLE_PATH" ]]; then
  echo "[ERROR] Gamma table not found: $GAMMA_TABLE_PATH" >&2
  echo "  Generate it first with:" >&2
  echo "    julia --project=. src/threshold_sensitivity.jl --gamma_table_generate auto --gamma_table_eps_list 0.005,0.01 ..." >&2
  exit 1
fi

echo "Using gamma table: $GAMMA_TABLE_PATH"
echo "Using eps_pof: $EPS_POF"

# Run Julia script (full parameters)
julia --project="$SLURM_SUBMIT_DIR" -t 1 src/threshold_sensitivity.jl \
  --idx_num 128 \
  --use_pof \
  --use_cvar \
  --eps_pof "$EPS_POF" \
  --lambda_pof 1.0 \
  --lambda_cvar 1.0 \
  --gamma_table_path "$GAMMA_TABLE_PATH" \
  --gamma_table_eps "$EPS_POF" \
  --niterations 20 \
  --threshold_num 10 \
  --threshold_min 2.0 \
  --threshold_max 6.0 \
  "${THRESH_ARGS[@]}"

echo "Job completed at $(date)"

