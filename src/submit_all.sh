#!/usr/bin/env bash
set -euo pipefail

# ------- 通用块：把一组 RISK_ARGS 以 CASE_TAG 名提交 -------
submit_case () {
  local CASE_TAG="$1"
  shift
  local RISK_ARGS="$*"

  echo "[SUBMIT] ${CASE_TAG}"
  sbatch --job-name="${CASE_TAG}" \
         --export=ALL,CASE_TAG="${CASE_TAG}",RISK_ARGS="${RISK_ARGS}" \
         optim_inject_pace.sh
}

# ------- 1) POF：5 个 eps 值（tau=0.05） -------
# 约定：硬约束 +（可包含软项，当前主要用硬约束）；lambda/kappa 常数
POF_BASE="--use_pof --pof_as_constraint \
          --lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50 \
          --risk_mode relative --weight_mode voltime"

submit_case "DT_POF_eps=0"      ${POF_BASE} --eps_pof 0
submit_case "DT_POF_eps=0.001"  ${POF_BASE} --eps_pof 0.001
submit_case "DT_POF_eps=0.01"   ${POF_BASE} --eps_pof 0.01
submit_case "DT_POF_eps=0.02"   ${POF_BASE} --eps_pof 0.02
submit_case "DT_POF_eps=0.05"   ${POF_BASE} --eps_pof 0.05

# ------- 2) CVaR：gamma ∈ {0.01, 0.02, 0.05} × alpha ∈ {1%,2%,5%} -------
# 约定：硬约束 + 软项（--cvar_soft），lambda/kappa 常数
CVAR_BASE="--use_cvar --cvar_as_constraint --cvar_soft \
           --lambda_cvar 3.0e9 --kappa_cvar 50 \
           --risk_mode relative --weight_mode voltime"

# γ = 0.01
submit_case "DT_CVaR_g=0.01_a=0.01" ${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.01
submit_case "DT_CVaR_g=0.01_a=0.02" ${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.02
submit_case "DT_CVaR_g=0.01_a=0.05" ${CVAR_BASE} --gamma_cvar 0.01 --alpha 0.05

# γ = 0.02
submit_case "DT_CVaR_g=0.02_a=0.01" ${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.01
submit_case "DT_CVaR_g=0.02_a=0.02" ${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.02
submit_case "DT_CVaR_g=0.02_a=0.05" ${CVAR_BASE} --gamma_cvar 0.02 --alpha 0.05

# γ = 0.05
submit_case "DT_CVaR_g=0.05_a=0.01" ${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.01
submit_case "DT_CVaR_g=0.05_a=0.02" ${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.02
submit_case "DT_CVaR_g=0.05_a=0.05" ${CVAR_BASE} --gamma_cvar 0.05 --alpha 0.05
