# 清理和分析总结

## 完成的工作

### 1. Lambda 选择分析

已创建分析文档：`lambda_selection_analysis.md`

**关键发现**：
- **POF cases**: `lambda_pof = 8.5e8` (8.5 × 10⁸)
- **CVaR cases**: `lambda_cvar = 3.0e9` (3.0 × 10⁹)
- CVaR 的 lambda 值约为 POF 的 3.5 倍

**使用场景**：
- POF cases: 832 jobs (10个不同的eps值 × 不同样本范围)
- CVaR cases: 1280 jobs (20个不同的alpha/gamma组合 × 64个样本)

### 2. Scripts 文件夹清理

**清理前**: 29 个 shell 脚本  
**清理后**: 22 个 shell 脚本  
**删除数量**: 7 个文件

#### 已删除的文件

1. `submit_11_cases_samples_2_64.sh` - 已被 `submit_11_cases_samples_2_64_smart.sh` 替代
2. `rerun_7_missing_cvar_samples.sh` - 已被 `rerun_7_missing_cvar_samples_fix.sh` 替代
3. `rerun_two_cases.sh` - 一次性重跑任务（已完成）
4. `rerun_2_failed_cases.sh` - 一次性重跑任务（已完成）
5. `rerun_5_completed_no_final.sh` - 一次性重跑任务（已完成）
6. `rerun_missing_cvar_samples.sh` - 一次性重跑任务（已完成）
7. `retry_failed_submissions.sh` - 一次性重试任务（已完成）

#### 保留的文件（22个）

**核心提交脚本**：
- `optim_inject_pace.sh` - 主要提交脚本
- `optim_inject_pace_7cases_fix.sh` - 修复版本
- `optim_inject_cruyff.sh` - Cruyff集群脚本
- `optim_inject_cruyff_cpu.sh` - Cruyff CPU脚本

**智能提交脚本**（当前使用）：
- `submit_pof_cases_smart.sh` - POF cases智能提交
- `submit_20_cases_samples_65_128_smart.sh` - CVaR cases智能提交
- `submit_11_cases_samples_2_64_smart.sh` - 智能提交脚本
- `submit_11_cases_samples_1_128.sh` - 提交脚本

**其他提交脚本**：
- `submit_all.sh` - 早期提交脚本（保留作为参考）
- `submit_pof_sensitivity.sh` - POF敏感性分析
- `submit_threshold_sensitivity.sh` - 阈值敏感性分析
- `submit_gamma_table_generation.sh` - Gamma表生成

**工具脚本**：
- `retry_failed_job.sh` - 通用重试工具（保留）
- `rerun_7_missing_cvar_samples_fix.sh` - 修复版本重跑脚本（保留）

**检查和验证脚本**：
- `check_7cases_inj_rate.sh`
- `check_7cases_outlier.sh`
- `check_submit_65_128_progress.sh`
- `verify_logs_path.sh`
- `verify_skip_from_log.sh`

**其他工具**：
- `run_plot_threshold_sensitivity.sh` - 绘图脚本
- `run_scaling_all.sh` - 扩展性测试
- `move_iteration_files_to_scratch.sh` - 文件管理

## 相关文档

- `lambda_selection_analysis.md` - Lambda 选择详细分析
- `scripts/shell/CLEANUP_PLAN.md` - 清理计划文档

## 建议

1. **Lambda 值**：建议在未来的提交中继续使用已验证的 lambda 值（`lambda_pof = 8.5e8`, `lambda_cvar = 3.0e9`）
2. **脚本维护**：定期清理已完成的一次性任务脚本，保持文件夹整洁
3. **文档更新**：如果进行 lambda 调优，建议更新 `lambda_selection_analysis.md`

