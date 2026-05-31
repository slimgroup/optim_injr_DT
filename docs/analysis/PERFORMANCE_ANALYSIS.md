# 运行时间分析 (Performance Analysis)

## 为什么运行时间这么长？

### 计算复杂度分析

1. **每个 objective 函数调用**：
   - 时间步数：`6 * ds * forward_step`（默认 `ds=10`, `forward_step=2` = 120 步）
   - 每个时间步需要运行一次完整的油藏模拟
   - **每个 objective 调用 ≈ 120 次模拟**

2. **每次优化迭代**：
   - 梯度计算：2-3 次 objective 调用（forward/central difference）
   - 线搜索：3-10 次 objective 调用（backtracking line search）
   - 状态更新：1 次 objective 调用
   - **每次迭代 ≈ 5-13 次 objective 调用**
   - **每次迭代 ≈ 600-1,560 次模拟**

3. **每个阈值**：
   - 默认 `niterations = 20`
   - **每个阈值 ≈ 100-260 次 objective 调用**
   - **每个阈值 ≈ 12,000-31,200 次模拟**

4. **整个敏感性分析**：
   - 如果 `threshold_num = 10` 个阈值
   - **总共 ≈ 1,000-2,600 次 objective 调用**
   - **总共 ≈ 120,000-312,000 次模拟**

### 估算运行时间

假设：
- 每次模拟耗时：0.1-1 秒（取决于网格大小和复杂度）
- 每个 objective 调用：12-120 秒
- 每次迭代：1-20 分钟
- 每个阈值：20-400 分钟（0.3-6.7 小时）
- 10 个阈值：3-67 小时

## 优化建议

### 1. 减少迭代次数（最快）
```bash
julia src/threshold_sensitivity.jl --niterations 5 --idx_num 128
```
- 从 20 次迭代减少到 5 次
- **速度提升：4x**
- 可能影响收敛精度

### 2. 使用 forward difference（较快）
```bash
julia src/threshold_sensitivity.jl --grad_forward --idx_num 128
```
- 梯度计算从 2 次减少到 1 次 objective 调用
- **速度提升：~1.5-2x**
- 梯度精度略低

### 3. 减少阈值数量（最快）
```bash
# 只测试 3 个阈值
julia src/threshold_sensitivity.jl --threshold_num 3 --idx_num 128
```
- **速度提升：3-10x**（取决于原来有多少阈值）

### 4. 减少时间步数（中等）
修改代码中的 `ds` 和 `forward_step`：
- `ds = 10` → `ds = 5`（时间步数减半）
- `forward_step = 2` → `forward_step = 1`（时间步数再减半）
- **速度提升：2-4x**
- 可能影响模拟精度

### 5. 组合优化（推荐）
```bash
julia src/threshold_sensitivity.jl \
  --niterations 10 \
  --grad_forward \
  --threshold_num 5 \
  --idx_num 128
```
- **综合速度提升：~6-12x**
- 预计运行时间：0.5-5 小时（取决于硬件）

### 6. 并行化（高级）
- 不同阈值可以并行运行
- 需要修改代码支持多进程/多线程
- **理论速度提升：Nx**（N = 并行阈值数）

## 检查当前运行状态

```bash
# 检查进度
julia scripts/julia_scripts/utilities/check_progress.jl 128

# 检查进程
ps aux | grep threshold_sensitivity

# 检查输出文件
ls -lth data/DT_control/exp_name=step1/threshold_sensitivity/
```

## 建议的工作流程

1. **快速测试**（验证代码正确性）：
   ```bash
   julia src/threshold_sensitivity.jl \
     --niterations 3 \
     --threshold_num 3 \
     --grad_forward \
     --idx_num 128
   ```

2. **中等规模**（平衡速度和精度）：
   ```bash
   julia src/threshold_sensitivity.jl \
     --niterations 10 \
     --threshold_num 5 \
     --grad_forward \
     --idx_num 128
   ```

3. **完整分析**（最高精度）：
   ```bash
   julia src/threshold_sensitivity.jl \
     --niterations 20 \
     --threshold_num 10 \
     --idx_num 128
   ```

## 监控运行时间

脚本会显示：
- 每个阈值的预计剩余时间
- 每个迭代的预计剩余时间
- 总体进度和预计完成时间

使用 `check_progress.jl` 可以随时查看进度。
