#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   src/submit_pof_sensitivity.sh
#   src/submit_pof_sensitivity.sh -s 17
#   src/submit_pof_sensitivity.sh -s 1-64

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"     # repo 根目录
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"  # 本目录下的 pace 脚本

# 默认样本范围 = 1-32（与你当前 optim_inject_pace.sh 保持一致）
SAMPLE_RANGE="1-32"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--samples)
      SAMPLE_RANGE="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"; exit 1;;
  esac
done

[[ -f "${SBATCH_FILE}" ]] || { echo "ERROR: 未找到 ${SBATCH_FILE}"; exit 1; }

# 公共 POF 参数
POF_BASE="--use_pof --pof_as_constraint \
          --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
          --risk_mode relative --weight_mode voltime"

# 你要新增的 5 个 eps
EPS_LIST=(0.0005 0.002 0.003 0.005 0.03)

DEP_OPT=""

submit_one () {
  local eps="$1"
  local tag="DT_POF_eps=${eps}"

  echo "[SUBMIT] ${tag}  samples=${SAMPLE_RANGE} ${DEP_OPT:+(dep ${DEP_OPT})}"
  jobline=$(sbatch ${DEP_OPT} --parsable --array="${SAMPLE_RANGE}" --chdir="${ROOT_DIR}" \
            --job-name="${tag}" \
            --export=ALL,CASE_TAG="${tag}",RISK_ARGS="${POF_BASE} --eps_pof ${eps}" \
            "${SBATCH_FILE}")
  jobid="${jobline%%_*}"
  echo "  -> jobid ${jobid}"
  DEP_OPT="--dependency=afterany:${jobid}"
}

for eps in "${EPS_LIST[@]}"; do
  submit_one "${eps}"
done
