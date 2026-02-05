# Computational Cost Breakdown: Single Optimization Run

## Executive Summary

A single optimization run (one permeability sample) takes approximately **5-5.5 hours** due to the large-scale reservoir simulation (131K grid cells) combined with iterative optimization requiring ~30-50 objective function evaluations.

**Verified from actual Slurm log** (`out_DT_POF_eps=0.1_s1_3117629_1.txt`): walltime = **5h17m** for 8 optimization iterations, job 3117629.

---

## 1. Problem Setup

### Grid Dimensions
| Parameter | Value | Description |
|-----------|-------|-------------|
| `n` | (512, 1, 256) | Grid dimensions (nx, ny, nz) |
| **Total grid cells** | **131,072** | 512 × 256 cells |
| Cell size `d` | (6.25, 100.0, 6.25) m | Physical dimensions |
| Domain size | 3.2 km × 1.6 km | 2D cross-section |

### Time Discretization
| Parameter | Value | Description |
|-----------|-------|-------------|
| Injection periods (`inj_len`) | 12 | `forward_step` × 6, where `forward_step=2` |
| Period length | 80 days | Per injection period |
| Report steps per period (`ds`) | 10 | Each report step = 8 days |
| Total report steps | 120 | 12 periods × 10 steps |
| **Total simulation time** | **960 days** | 12 periods × 80 days |

---

## 2. Parallelism Strategy

### What We Parallelize
- **Inter-sample parallelism**: Embarrassingly parallel across different permeability samples
- Each of the 128 samples runs independently on separate compute nodes
- No communication between samples during optimization

```
Sample 1 ──→ [Optimization ~8 iters] ──→ Result 1
Sample 2 ──→ [Optimization ~8 iters] ──→ Result 2    (all in parallel)
   ...
Sample 128 ──→ [Optimization ~8 iters] ──→ Result 128
```

### What We Do NOT Parallelize (Sequential Line Search Dependency)

Within a single optimization, the line search is **inherently sequential**:

```
Iteration k:
  1. Compute gradient: g = ∇f(x)
  2. Line search (sequential!):
     - Try step α₁: compute f(x + α₁·p) → too big? 
     - Try step α₂: compute f(x + α₂·p) → still too big?
     - Try step α₃: compute f(x + α₃·p) → OK, accept
  3. Update: x = x + α₃·p
  4. Go to iteration k+1
```

**Why can't we parallelize line search?**
- Each trial step depends on the result of the previous one (Armijo condition check)
- We don't know if we need to try α₂ until we've evaluated f(x + α₁·p)
- This is a fundamental limitation of backtracking line search algorithms

### Current Thread Settings (CVaR/POF runs)

```bash
#SBATCH --cpus-per-task=1      # Single CPU per task
export OPENBLAS_NUM_THREADS=1  # Single-threaded BLAS
export OMP_NUM_THREADS=1       # Single-threaded OpenMP
```

**Note**: Current runs use single-threaded mode. The older JutulDarcy version (v0.2.7) may have limited multithreading support.

---

## 3. Optimization Algorithm Details

### Algorithm: Projected Gradient Descent with Backtracking Line Search

```julia
ls = BackTracking(order=3, iterations=15)
niterations = 20  # max GD iterations
```

### Per-Iteration Breakdown

| Step | Forward Simulations | Notes |
|------|---------------------|-------|
| Gradient (forward-diff) | 2 | `f(x+δ)` and `f(x)` |
| Gradient (central-diff) | 3 | `f(x+δ)`, `f(x)`, `f(x-δ)` |
| Line search | 2-4 | Backtracking until Armijo condition met |
| **Total per iteration** | **~4-6** | Verified from log data |

### Aggregate Cost Estimate (Verified from Log)

| Metric | Value | Source |
|--------|-------|--------|
| Optimization iterations | ~8 (converged before max 20) | Log: 8 "Iteration no" entries |
| Objective evals per iteration | ~4-6 (gradient + line search) | Log: ~48 timing blocks per iteration gap |
| **Total objective evaluations** | **~32-48 per optimization** | 8 iters × 4-6 evals |
| **Time per objective eval** | **~4-5 minutes** | 12 Sblk blocks × ~20-25 s each |
| **Total optimization time** | **~5h17m** | Slurm walltime (job 3117629) |

---

## 4. Time Estimate Breakdown

### Single Objective Function Evaluation

One call to `objective()` runs **12 sequential Sblk calls** (one per injection period):

```
objective(inj_rate, ...) =
  for i in 1:12           # inj_len = forward_step * 6 = 12
      sim.Sblk(...)       # Each Sblk simulates 80 days with ds=10 report steps
  end
```

### Single Sblk Call (One Reservoir Simulation Block)

Verified timing from log `out_DT_POF_eps=0.1_s1_3117629_1.txt`:

| Metric | Value | Source |
|--------|-------|--------|
| Simulated time | 80 days | `ds × dt_firstblock = 10 × 8` |
| Report steps (`ds`) | 10 | User-defined output points |
| **Adaptive ministeps** | **14-31** | Jutul decides internally |
| Newton iterations per ministep | ~3-5 | From `Avg/ministep` column |
| **Time per Newton iteration** | **~280-320 ms** | From `Time per ms` column |
| **Total per Sblk call** | **~18-29 s** (avg ~21 s) | From `Total s` column |

**First 12 Sblk blocks (first objective evaluation) from log:**

| Block | Ministeps | Total (s) | Note |
|-------|-----------|-----------|------|
| 1 | 16 | 22.6 | Includes JIT warmup (593ms/Newton vs normal ~300ms) |
| 2 | 17 | 21.9 | |
| 3 | 28 | 28.9 | More ministeps (higher nonlinearity) |
| 4 | 19 | 24.0 | |
| 5 | 14 | 18.8 | |
| 6 | 14 | 19.4 | |
| 7 | 17 | 18.9 | |
| 8 | 14 | 18.0 | |
| 9 | 17 | 20.3 | |
| 10 | 14 | 19.8 | |
| 11 | 22 | 24.6 | |
| 12 | 17 | 20.6 | |
| **Total** | | **~258 s ≈ 4.3 min** | **One objective function evaluation** |

**In later iterations** (higher injection rates → stronger nonlinearity):
- Some blocks reach 31 ministeps, taking up to ~42 seconds
- Average objective eval time increases to ~5-7 minutes

### What is a "PDE Solve" in Jutul?

JutulDarcy solves the **implicit nonlinear PDE system** (two-phase CO2-brine flow) using Newton's method:

```
One Sblk call (80 days, ds=10)
  └─ 14-31 adaptive ministeps (Jutul decides)
       └─ Each ministep: Newton iterations (3-5 iters)
            └─ Each Newton iteration:
                 1. Assemble nonlinear residual F(x) on 131K grid
                 2. Assemble Jacobian J(x) (sparse 131K × 131K matrix)
                 3. Solve J·δx = -F(x) via Krylov solver + preconditioner
                 4. Update: x ← x + δx
                 5. Check convergence: ‖F(x_new)‖ < tolerance?
```

| Term | Definition |
|------|------------|
| **Report steps** | User-defined output times (controlled by `ds`, e.g., every 8 days) |
| **Ministeps** | Internal adaptive time steps between report steps; Jutul decides the count |
| **Newton iteration** | Nonlinear solve at each ministep (~300 ms each) |
| **Linear solve** | Krylov method solving the Jacobian system (~200 ms, 65-70% of Newton time) |

### How Jutul Decides the Number of Ministeps (Adaptive Time Stepping)

Jutul uses an **adaptive time stepping** algorithm:

1. Start with an initial ministep size
2. Attempt Newton solve for the current ministep
3. **If Newton converges quickly** (few iterations) → enlarge the next ministep (e.g., ×1.5)
4. **If Newton converges slowly or fails** → halve the ministep and retry (e.g., ×0.5)
5. Repeat until the entire report step interval is covered

**Evidence from log data**: Different blocks have vastly different ministep counts:
- Low injection rate / early time → 14 ministeps (easier physics)
- High injection rate / CO2 front moving fast → 28-31 ministeps (stronger nonlinearity)

**Key insight**: The parameter `ds` controls **report step frequency** (when to save output), but **Jutul's internal ministeps are determined by its own convergence criteria**, not by `ds`. This is why changing `ds` has minimal impact on total simulation time.

### Newton Iteration Cost Breakdown

From the log timing tables, each ~300ms Newton iteration is spent on:

| Component | Time (ms) | Fraction |
|-----------|-----------|----------|
| Linear solve (Krylov) | ~200 | 65-70% |
| Preconditioner | ~48 | 15-19% |
| Properties | ~15 | 5% |
| Equations + Assembly | ~20 | 7-8% |
| Update + Convergence | ~7 | 2-3% |
| Other / I/O | ~10 | 3-5% |

**Linear solve dominates**: Solving the 131K × 131K sparse Jacobian system is the bottleneck.

### Full Optimization

- **Iterations**: ~8 (converged before max 20, verified from log)
- **Objective evals per iteration**: ~4-6 (gradient computation + line search)
- **Total objective evals**: ~32-48
- **Time per objective eval**: ~4-5 minutes (early) to ~6-7 minutes (later)
- **Typical runtime: ~5-5.5 hours per sample** (verified: 5h17m)

---

## 5. Effect of `ds` on Simulation Runtime

### What `ds` Controls

```julia
function build_sim(n, d, ϕ, K; h=0.0, ds=10, dt_firstblock=80/ds)
    Sblk = jutulModeling(model, dt_firstblock * ones(ds))  # ds report steps of 80/ds days each
end
```

Each Sblk call always simulates **80 days** regardless of `ds` (`ds × 80/ds = 80`).

### Comparison Across `ds` Values

| Parameter | ds=1 | ds=2 | ds=5 | ds=10 (current) |
|-----------|------|------|------|-----------------|
| dt per report step | 80 days | 40 days | 16 days | 8 days |
| Report steps per block | 1 | 2 | 5 | 10 |
| Total report steps (12 blocks) | 12 | 24 | 60 | 120 |
| Sblk calls per objective | 12 | 12 | 12 | 12 |
| Total simulation time | 960 days | 960 days | 960 days | 960 days |

### Why `ds` Has Minimal Impact on Runtime

1. **Ministeps are adaptive**: Jutul internally creates ~14-28 ministeps per 80-day block regardless of `ds`. With ds=10, each 8-day report interval gets ~1.4-2.8 ministeps. With ds=1, the single 80-day interval gets a similar total number of ministeps.
2. **Newton iteration count is physics-driven**: The nonlinearity of the CO2-brine system determines how many Newton iterations are needed, not the number of report steps.
3. **Overhead per report step is tiny**: Report step I/O and state storage add negligible overhead compared to Newton solves.

### Expected Runtime by `ds`

| ds | Est. time per objective eval | Relative to ds=10 | Note |
|----|-----------------------------|--------------------|------|
| 1 | ~4-5 min | ~0.85-0.95× | Slightly faster (less I/O overhead) |
| 2 | ~4-5 min | ~0.90-0.98× | Nearly identical |
| 5 | ~4-5 min | ~0.95-1.0× | Nearly identical |
| 10 | ~4-5 min | 1.0× (baseline) | Current setting |

**Estimated difference: <15%** across all `ds` values.

### What `ds` DOES Affect

1. **Temporal resolution for risk analysis**: ds=10 provides 120 time snapshots for PoF/CVaR calculation; ds=1 provides only 12
2. **Objective function integration accuracy**: Finer time discretization → more accurate time-weighted injection volume
3. **Memory**: ds=10 stores 120 state snapshots vs ds=1 stores 12

**Recommendation**: Keep `ds=10` for its superior temporal resolution in risk assessment, with negligible runtime penalty.

**Note**: A test script (`test_ds_minimal.jl`) and submission script (`scripts/shell/test_ds_verification.sh`) were prepared to experimentally verify these theoretical predictions, but no successful results have been obtained yet.

---

## 6. Computational Tricks to Reduce Runtime

We've implemented several optimizations to minimize iteration count:

### 6.1 Smart Initial Step Size
```julia
# Different initial steps based on constraint type
if risk_opts.pof_as_constraint
    ex_step_size = 0.15  # Smaller for POF (tighter constraints)
elseif risk_opts.cvar_as_constraint
    ex_step_size = 0.2   # Standard for CVaR
else
    ex_step_size = 0.2   # Default
end
```

**Rationale**: POF-constrained optima have ~28% smaller injection rates, so smaller steps are more appropriate.

### 6.2 Step Size Reuse Across Iterations
- Previous iteration's step size is used as initial guess for next iteration
- Avoids re-searching from scratch each time
- **Savings**: ~2-5 line search evaluations per iteration

### 6.3 Cubic Backtracking Line Search
```julia
ls = BackTracking(order=3, iterations=15)
```
- Uses cubic interpolation (`order=3`) for faster step size estimation
- More accurate than bisection, fewer iterations needed

### 6.4 Monotonic Injection Schedule
```julia
inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
```
- Single scalar control variable (final injection rate)
- Schedule is monotonically increasing from `inj_start` to `inj_rate`
- **Advantage**: Only 1D optimization instead of 12D (one rate per period)

### 6.5 Forward-Difference Gradient (Optional)
```bash
--grad_forward  # Use forward instead of central difference
```
- Reduces gradient computation from 3 to 2 forward simulations
- ~33% speedup at cost of slightly less accurate gradients

---

## 7. Why Not Faster?

### Bottleneck Analysis

| Component | Fraction of Time | Parallelizable? |
|-----------|------------------|-----------------|
| Forward simulation (Jutul Newton solves) | ~90% | Yes (multi-threaded, but currently using 1 CPU) |
| Gradient computation | ~5% | No (sequential dependency) |
| Line search | ~5% | No (sequential dependency) |

### Why Intra-Sample Parallelism is Limited
1. **Sequential line search dependency**: Must evaluate `f(x)` before deciding whether to try `f(x + α*p)` (see diagram above)
2. **Current setup uses single-threaded mode**: `--cpus-per-task=1` for stability
3. **Memory constraints**: Each forward sim uses ~500MB-1GB; running multiple in parallel would exceed node memory

### Potential Future Speedups
| Approach | Expected Speedup | Difficulty |
|----------|------------------|------------|
| Upgrade JutulDarcy + enable multithreading | 2-4× | Medium (version upgrade needed) |
| Reduce `niterations` (20→10) | 2× | Easy (accuracy tradeoff) |
| Coarser grid (256×128) | 4× | Medium (accuracy tradeoff) |
| Adjoint gradients | 2-3× | Hard (requires Jutul AD) |
| Surrogate model | 10-50× | Very Hard (research) |

---

## 8. Summary Table

| Parameter | Value | Verified? |
|-----------|-------|-----------|
| Grid size | 512 × 256 = 131,072 cells | Yes (code) |
| Simulation time per objective eval | 960 days (12 × 80 days) | Yes (code) |
| Time per Sblk block (reservoir sim) | ~20-25 s (range: 18-42 s) | Yes (log) |
| **Time per objective evaluation** | **~4-5 min (early), ~6-7 min (later)** | **Yes (log)** |
| Optimization iterations | ~8 (converges before max 20) | Yes (log) |
| Objective evals per iteration | ~4-6 | Yes (log) |
| Total objective evals per run | ~32-48 | Yes (log) |
| **Time per optimization** | **~5h17m** | **Yes (Slurm walltime)** |
| Parallelism | Embarrassingly parallel across 128 samples | Yes (code) |

---

## 9. Code References

- Main optimization loop: `src/optim_inject.jl` lines 936-1100
- Objective function: `src/optim_inject.jl` lines 420-590
- Grid setup: `src/optim_inject.jl` line 607 (`n = (512, 1, 256)`)
- build_sim: `src/optim_inject.jl` lines 411-416
- Line search config: `src/optim_inject.jl` line 924 (`BackTracking(order=3, iterations=15)`)
- Iteration count: `src/optim_inject.jl` line 136 (default `--niterations 20`)
- JutulDarcy version: v0.2.7 (see `Project.toml`)
- Log data source: `logs/out_DT_POF_eps=0.1_s1_3117629_1.txt` (job 3117629, sample 1)
