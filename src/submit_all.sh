#!/usr/bin/env bash
set -euo pipefail

# 计算 repo 根目录和 sbatch 文件路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SBATCH_FILE="${SCRIPT_DIR}/optim_inject_pace.sh"

if [[ ! -f "${SBATCH_FILE}" ]]; then
  echo "ERROR: 找不到 ${SBATCH_FILE}"
  exit 1
fi

# 串联提交，避免 QOS submit 上限
submit_chain () {
  local CASE_TAG="$1"; shift
  local RISK_ARGS="$*"
  local DEP_OPT="${DEP_OPT:-}"

  echo "[SUBMIT] ${CASE_TAG} ${DEP_OPT:+(dep ${DEP_OPT})}"
  JOBLINE=$(sbatch ${DEP_OPT} --chdir="${ROOT_DIR}" \
           --job-name="${CASE_TAG}" \
           --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}" \
           "${SBATCH_FILE}")
  JOBID=$(awk '{print $4}' <<< "${JOBLINE}")
  echo "  -> jobid ${JOBID}"
  DEP_OPT="--dependency=afterany:${JOBID}"
}

# ------- 1) POF 五个 eps -------
POF_BASE="--use_pof --pof_as_constraint \
          --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
          --risk_mode relative --weight_mode voltime"

DEP_OPT=""
submit_chain "DT_POF_eps=0"      ${POF_BASE} --eps_pof 0
submit_chain "DT_POF_eps=0.001"  ${POF_BASE} --eps_pof 0.001
submit_chain "DT_POF_eps=0.01"   ${POF_BASE} --eps_pof 0.01
submit_chain "DT_POF_eps=0.02"   ${POF_BASE} --eps_pof 0.02
submit_chain "DT_POF_eps=0.05"   ${POF_BASE} --eps_pof 0.05

# ------- 2) CVaR 九个 (γ×α 组合) -------
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

submit_chain "DT_CVaR_g=0.01_a=0.01" ${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.01
submit_chain "DT_CVaR_g=0.01_a=0.02" ${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.02
submit_chain "DT_CVaR_g=0.01_a=0.05" ${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.05

submit_chain "DT_CVaR_g=0.02_a=0.01" ${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.01
submit_chain "DT_CVaR_g=0.02_a=0.02" ${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.02
submit_chain "DT_CVaR_g=0.02_a=0.05" ${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.05

submit_chain "DT_CVaR_g=0.05_a=0.01" ${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.01
submit_chain "DT_CVaR_g=0.05_a=0.02" ${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.02
submit_chain "DT_CVaR_g=0.05_a=0.05" ${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.05
