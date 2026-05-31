# SLURM 脚本代码解释

这个文档解释的是某一类 SLURM 脚本写法细节，不是当前仓库所有脚本的总导航。
如果你想先判断“应该从哪个脚本入口开始”，请先看 `docs/reference/SCRIPTS_INDEX.md`。

## 第 19-39 行代码详解

### 第 19 行：`set -euo pipefail`
```bash
set -euo pipefail
```
**作用**：设置 Bash 严格模式
- `-e`：遇到错误立即退出（任何命令返回非零状态码）
- `-u`：使用未定义变量时报错
- `-o pipefail`：管道中任何命令失败都会导致整个管道失败

**为什么需要**：确保脚本在出错时立即停止，避免继续执行导致更严重的问题。

---

### 第 20 行：`module purge`
```bash
module purge
```
**作用**：清除所有已加载的模块

**为什么需要**：确保干净的环境，避免不同模块版本之间的冲突。

---

### 第 21 行：`module load julia/1.11.3`
```bash
module load julia/1.11.3 2>/dev/null || true
```
**作用**：加载 Julia 1.11.3 模块
- `2>/dev/null`：将错误输出重定向到 /dev/null（静默处理）
- `|| true`：如果加载失败，不退出脚本（因为可能已经加载了）

**为什么需要**：确保使用正确的 Julia 版本。

---

### 第 24 行：`export JULIA_DEPOT_PATH="$HOME/julia-depot"`
```bash
export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
```
**作用**：设置 Julia 包存储路径
- `JULIA_DEPOT_PATH`：告诉 Julia 在哪里存储和查找包
- `mkdir -p`：如果目录不存在则创建

**是否有必要**：
- ✅ **推荐保留**：在集群环境中，使用独立的 depot 路径可以：
  1. 避免不同项目之间的包冲突
  2. 避免共享文件系统的权限问题
  3. 更好地管理包缓存
- ❌ **可以移除**：如果使用项目本地的包管理（`--project`），Julia 会优先使用项目目录下的包

**建议**：**保留**，特别是在 PACE 这样的共享集群环境中。

---

### 第 25 行：`export PYTHON=...`
```bash
export PYTHON=/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python
```
**作用**：指定 PyCall 使用的 Python 解释器路径

**为什么需要**：Julia 的 PyCall 包需要知道使用哪个 Python。在 PACE 上，必须使用系统提供的 Python，而不是用户安装的版本。

---

### 第 26 行：`export JULIA_PKG_PRECOMPILE_AUTO=0`
```bash
export JULIA_PKG_PRECOMPILE_AUTO=0
```
**作用**：禁用 Julia 包的自动预编译

**为什么需要**：
- 在集群环境中，自动预编译可能导致：
  1. 启动时间变长
  2. 磁盘 I/O 增加
  3. 不同节点之间的不一致性
- 禁用后，Julia 只在需要时编译，更可控。

---

### 第 27 行：`export MPLBACKEND=Agg`
```bash
export MPLBACKEND=Agg
```
**作用**：设置 Matplotlib 的后端为 Agg（非交互式）

**为什么需要**：
- 在无显示器的集群环境中，不能使用交互式后端（如 TkAgg）
- Agg 是纯图像后端，适合生成 PNG/PDF 等文件
- 避免 "No display" 错误

---

### 第 28-29 行：线程数限制
```bash
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
```
**作用**：限制线性代数库和 OpenMP 的线程数为 1

**为什么需要**：
1. **避免过度订阅**：SLURM 已经分配了 `--cpus-per-task=8`，但 Julia 内部可能使用多线程
2. **避免竞争**：多个线程库同时使用多线程会导致性能下降
3. **单线程绘图**：确保绘图操作是单线程的，避免竞争条件

---

### 第 30 行：`mkdir -p logs`
```bash
mkdir -p logs
```
**作用**：创建日志目录（如果不存在）

**为什么需要**：确保日志文件有地方写入。

---

### 第 32 行：`trap '...' TERM`
```bash
trap 'echo "[WARN] SIGTERM received; try to save…"' TERM
```
**作用**：设置信号处理，当收到 TERM 信号时执行清理操作

**为什么需要**：
- SLURM 在作业超时前会发送 TERM 信号（`--signal=TERM@60` 表示提前 60 秒发送）
- 这给了脚本机会保存中间结果，而不是直接被杀掉

---

### 第 35 行：`cd "$SLURM_SUBMIT_DIR"`
```bash
cd "$SLURM_SUBMIT_DIR"
```
**作用**：切换到作业提交时的目录

**为什么需要**：确保脚本在正确的项目目录中运行，相对路径能正常工作。

---

### 第 37-38 行：输出信息
```bash
echo "Job started at $(date)"
echo "Running threshold sensitivity analysis (fast mode)"
```
**作用**：记录作业开始时间和模式

**为什么需要**：方便在日志中查看作业状态。

---

## 关于 JULIA_DEPOT_PATH 的建议

### 保留的理由（推荐）：
1. **隔离性**：不同项目的包不会互相干扰
2. **权限**：避免在共享文件系统上的权限问题
3. **缓存管理**：更容易清理和管理包缓存
4. **集群环境**：在 PACE 这样的共享环境中更安全

### 可以移除的情况：
- 如果项目完全使用本地包管理（`--project`）
- 如果所有包都在项目目录下
- 如果不需要包缓存

### 建议：
**保留**，但可以简化：
```bash
# 简化版本（如果项目使用本地包管理）
# export JULIA_DEPOT_PATH="$HOME/julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
```

或者使用项目本地的 depot：
```bash
export JULIA_DEPOT_PATH="$SLURM_SUBMIT_DIR/.julia-depot"; mkdir -p "$JULIA_DEPOT_PATH"
```
