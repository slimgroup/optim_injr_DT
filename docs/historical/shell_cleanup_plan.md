# Scripts Cleanup Plan

## 文件分类

### 保留的文件（核心功能）
- `optim_inject_pace.sh` - 主要提交脚本
- `optim_inject_pace_7cases_fix.sh` - 修复版本
- `optim_inject_cruyff.sh` - Cruyff集群脚本
- `optim_inject_cruyff_cpu.sh` - Cruyff CPU脚本
- `submit_pof_cases_smart.sh` - PoF cases智能提交（当前使用）
- `submit_20_cases_samples_65_128_smart.sh` - CVaR cases智能提交（当前使用）
- `submit_11_cases_samples_2_64_smart.sh` - 智能提交脚本
- `submit_11_cases_samples_1_128.sh` - 提交脚本
- `submit_pof_sensitivity.sh` - PoF敏感性分析
- `submit_threshold_sensitivity.sh` - 阈值敏感性分析
- `submit_gamma_table_generation.sh` - Gamma表生成
- `check_7cases_inj_rate.sh` - 检查脚本
- `check_7cases_outlier.sh` - 检查脚本
- `check_submit_65_128_progress.sh` - 进度检查
- `verify_logs_path.sh` - 日志验证
- `verify_skip_from_log.sh` - 日志跳过验证
- `run_plot_threshold_sensitivity.sh` - 绘图脚本
- `run_scaling_all.sh` - 扩展性测试
- `move_iteration_files_to_scratch.sh` - 文件管理

### 可删除的文件（旧版本或一次性任务）

#### 旧版本（已被smart版本替代）
- `submit_11_cases_samples_2_64.sh` - 已被smart版本替代
- `rerun_7_missing_cvar_samples.sh` - 已被fix版本替代

#### 一次性重跑脚本（任务已完成）
- `rerun_two_cases.sh` - 特定两个case的重跑
- `rerun_2_failed_cases.sh` - 特定失败case的重跑
- `rerun_5_completed_no_final.sh` - 特定case的重跑
- `rerun_missing_cvar_samples.sh` - 缺失样本的重跑
- `retry_failed_submissions.sh` - 失败提交的重试（一次性）

#### 可能保留的工具脚本
- `retry_failed_job.sh` - 通用工具，可能还有用（保留）
- `submit_all.sh` - 早期提交脚本，可能还有参考价值（保留）

## 清理执行

### 已删除的文件（2025-01-XX）

以下文件已被删除：

1. ✅ `submit_11_cases_samples_2_64.sh` - 已被smart版本替代
2. ✅ `rerun_7_missing_cvar_samples.sh` - 已被fix版本替代
3. ✅ `rerun_two_cases.sh` - 一次性重跑任务已完成
4. ✅ `rerun_2_failed_cases.sh` - 一次性重跑任务已完成
5. ✅ `rerun_5_completed_no_final.sh` - 一次性重跑任务已完成
6. ✅ `rerun_missing_cvar_samples.sh` - 一次性重跑任务已完成
7. ✅ `retry_failed_submissions.sh` - 一次性重试任务已完成

### 清理结果

- **清理前**: 29 个 shell 脚本
- **清理后**: 22 个 shell 脚本
- **删除数量**: 7 个文件

### 保留的文件说明

以下文件被保留，因为它们可能还有用：
- `retry_failed_job.sh` - 通用工具，可用于重试单个失败任务
- `submit_all.sh` - 早期提交脚本，可能有参考价值
- `rerun_7_missing_cvar_samples_fix.sh` - 修复版本，可能还在使用

