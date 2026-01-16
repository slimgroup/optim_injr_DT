# Computational Cost Breakdown: Single Optimization Run

## Executive Summary

A single optimization run (one permeability sample) takes approximately **6 hours** due to the large-scale reservoir simulation (131K grid cells) combined with iterative optimization requiring ~50-100 forward simulations.

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
| Injection periods | 12 | 6 × `forward_step` |
| Period length | 80 days | Per injection period |
| **Total simulation time** | **960 days** | 12 periods × 80 days |

---

## 2. Parallelism Strategy

### What We Parallelize
- **Inter-sample parallelism**: Embarrassingly parallel across different permeability samples
- Each of the 128 samples runs independently on separate compute nodes
- No communication between samples during optimization

```
Sample 1 ──→ [Optimization ~15 iters] ──→ Result 1
Sample 2 ──→ [Optimization ~15 iters] ──→ Result 2    (all in parallel)
   ...
Sample 128 ──→ [Optimization ~15 iters] ──→ Result 128
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
| Line search | 3-15 | Backtracking until Armijo condition met |
| **Total per iteration** | **5-17** | Depending on line search difficulty |

### Aggregate Cost Estimate

| Metric | Value |
|--------|-------|
| Optimization iterations | ~10-15 (often converges before max 20) |
| Forward sims per iteration | ~5-7 (gradient + line search) |
| **Total forward simulations** | **~50-100 per optimization** |
| **Time per forward sim** | **~2-3 minutes** |
| **Total optimization time** | **~6 hours** |

---

## 4. Time Estimate Breakdown

### Single Forward Simulation
- **Grid**: 131,072 cells
- **Simulation time**: 960 days
- **Solver**: JutulDarcy (implicit finite volume)
- **Time per forward sim**: ~2-3 minutes

### What is a "PDE Solve" in Jutul?

JutulDarcy uses adaptive time stepping internally:

| Term | Definition |
|------|------------|
| **Report steps** | User-defined output times (e.g., end of each injection period) |
| **Substeps (ministeps)** | Internal mini-time-steps that Jutul creates adaptively between report steps |
| **Newton iteration** | Iterative solver for the nonlinear PDE system at each substep |
| **Linear solve** | Solving the Jacobian system within each Newton iteration |

**One "PDE solve" = one substep**, which includes:
1. Assemble the nonlinear residual on 131K grid
2. Newton iterations until convergence (typically 3-10 iterations)
3. Each Newton iteration requires a linear solve (Krylov + preconditioner)

**Key insight**: The parameter `ds` controls report step frequency, but **Jutul's internal substeps are determined by its own convergence criteria and adaptive time stepping**, not directly by `ds`. This explains why `ds=10` vs `ds=1` gives similar simulation times—Jutul automatically adjusts the number and size of substeps to maintain numerical stability.

**Note**: Using JutulDarcy v0.2.7 (older version), which may have limited multithreading support.

### Full Optimization

- **Iterations**: ~10-15 (typically converges before max 20)
- **Forward sims per iteration**: ~5-7 (gradient computation + line search)
- **Total forward sims**: ~50-100
- **Typical runtime: ~6 hours per sample**

---

## 5. Computational Tricks to Reduce Runtime

We've implemented several optimizations to minimize iteration count:

### 5.1 Smart Initial Step Size
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

### 5.2 Step Size Reuse Across Iterations
- Previous iteration's step size is used as initial guess for next iteration
- Avoids re-searching from scratch each time
- **Savings**: ~2-5 line search evaluations per iteration

### 5.3 Cubic Backtracking Line Search
```julia
ls = BackTracking(order=3, iterations=15)
```
- Uses cubic interpolation (`order=3`) for faster step size estimation
- More accurate than bisection, fewer iterations needed

### 5.4 Monotonic Injection Schedule
```julia
inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
```
- Single scalar control variable (final injection rate)
- Schedule is monotonically increasing from `inj_start` to `inj_rate`
- **Advantage**: Only 1D optimization instead of 12D (one rate per period)

### 5.5 Forward-Difference Gradient (Optional)
```bash
--grad_forward  # Use forward instead of central difference
```
- Reduces gradient computation from 3 to 2 forward simulations
- ~33% speedup at cost of slightly less accurate gradients

---

## 6. Why Not Faster?

### Bottleneck Analysis

| Component | Fraction of Time | Parallelizable? |
|-----------|------------------|-----------------|
| Forward simulation (Jutul) | ~90% | Yes (multi-threaded, but currently using 1 CPU) |
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

## 7. Summary Table

| Parameter | Value |
|-----------|-------|
| Grid size | 512 × 256 = 131,072 cells |
| Simulation time | 960 days |
| Optimization iterations | ~10-15 (converges before max 20) |
| Forward sims per iteration | ~5-7 |
| Total forward sims per run | ~50-100 |
| Time per forward sim | ~2-3 minutes |
| **Time per optimization** | **~6 hours** |
| Parallelism | Embarrassingly parallel across 128 samples |

---

## 8. Code References

- Main optimization loop: `src/optim_inject.jl` lines 936-1100
- Grid setup: `src/optim_inject.jl` line 607 (`n = (512, 1, 256)`)
- Line search config: `src/optim_inject.jl` line 924 (`BackTracking(order=3, iterations=15)`)
- Iteration count: `src/optim_inject.jl` line 136 (default `--niterations 20`)
- JutulDarcy version: v0.2.7 (see `Project.toml`)

