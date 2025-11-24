#!/bin/bash
# 快速运行阈值敏感性分析（启用 POF + CVaR，自动校准）

julia src/threshold_sensitivity.jl \
  --idx_num 128 \
  --use_pof \
  --use_cvar \
  --eps_pof 0.01 \
  --lambda_pof 1.0 \
  --lambda_cvar 1.0 \
  --calibrate_gamma \
  --niterations 10 \
  --grad_forward \
  --threshold_num 5 \
  --threshold_min 2.0 \
  --threshold_max 6.0
