# Step-2 实验：进度与日志位置

## 如何查进度

### 方法一：用脚本一次性看

在**项目根目录**执行：

```bash
bash scripts/shell/check/check_step2_progress.sh
```

会输出：当前队列里的 step2 任务、各 case 的 `final.jld2` 完成数量、日志目录和常用命令。

### 方法二：自己敲命令

- **看队列（正在跑 / 在等）：**
  ```bash
  squeue -u $USER
  ```
  只看 step2 相关 job 名：
  ```bash
  squeue -u $USER | grep step2
  ```

- **看历史（已结束的任务）：**
  ```bash
  sacct -u $USER --format=JobID,JobName%36,State,Elapsed,ExitCode -S $(date -d '1 day ago' +%Y-%m-%d)
  ```

- **看结果完成情况：**  
  step2 的结果在 `data/DT_control/exp_name=step2/<case_tag>/sample=<s>/final.jld2`，例如：
  ```bash
  data/DT_control/exp_name=step2/
  ├── case=pof_eps0.01__prior=pointwise_median__POF__HARD__...
  │   └── sample=s1/, sample=s2/, ...  (每个里有 final.jld2)
  ├── case=pof_eps0.01__prior=paired_posterior_sample__...
  ├── case=cvar_g0.1_a0.01__prior=pointwise_median__...
  └── case=cvar_g0.1_a0.01__prior=paired_posterior_sample__...
  ```
  统计某个 case 完成数：
  ```bash
  find data/DT_control/exp_name=step2 -name "final.jld2" | wc -l
  ```

---

## Logs 存在哪里

### 1. SLURM 的 stdout / stderr（你看到的 “logs”）

在 `optim_inject_pace.sh` 里写的是：

- `#SBATCH --output=../logs/out_%x_%A_%a.txt`
- `#SBATCH --error=../logs/err_%x_%A_%a.txt`

这里的路径是**相对你提交任务时所在目录**的：

- **如果你是在项目根目录提交的**（例如 `bash scripts/shell/submit/submit_step2_dual_prior_smoketest.sh`）：  
  日志在 **项目根目录的上一级目录里的 `logs`**，即：
  ```text
  <项目根目录>/../logs/
  ```
  例如项目根是 `/storage/project/r-fherrmann9-0/hli853/optim_injr_DT`，则 logs 在：
  ```text
  /storage/project/r-fherrmann9-0/hli853/logs/
  ```
  里面的文件类似：`out_DT_step2_POF_eps=0.01_prior=pointwise_median_4971483_1.txt`（job 名 + job id + array index）。

- **如果你是在 `scripts/shell` 下提交的**（例如 `cd scripts/shell && bash submit_step2_dual_prior_smoketest.sh`）：  
  则 `../logs` 表示 `scripts/logs`。

### 2. 项目里的 `logs/`

脚本里还会在项目根下建 `logs/` 目录（`mkdir -p "${PROJECT_ROOT}/logs"`），但 **SLURM 的 stdout/stderr 不会写进这里**，除非你改过 `#SBATCH --output/--error`。所以：

- 查 **SLURM 打印出来的内容**：以 `#SBATCH` 里的路径为准，即上面的 `../logs`。
- 项目根下的 `logs/` 可能被别的脚本或你本地测试用。

### 3. 迭代/中间结果（JLD2）

- **最终结果**：`data/DT_control/exp_name=step2/<case_tag>/sample=s*/final.jld2`
- **按迭代存的中间结果**：在 **scratch** 下，例如：
  ```text
  $SCRATCH/optim_injr_DT/DT_control/exp_name=step2/<case_tag>/sample=s*/
  ```
  若没设 `SCRATCH`，代码里默认是 `/storage/home/hcoda1/6/<user>/scratch`。

---

## 小结

| 内容           | 位置 |
|----------------|------|
| SLURM 标准输出/错误 | 提交时当前目录的 `../logs/`（从项目根提交则为 `<项目根>/../logs/`） |
| 各 case 结果   | `data/DT_control/exp_name=step2/<case_tag>/sample=s*/final.jld2` |
| 迭代中间文件   | `$SCRATCH/optim_injr_DT/DT_control/exp_name=step2/...` |

查进度最快的方式：在项目根执行一次  
`bash scripts/shell/check/check_step2_progress.sh`。
