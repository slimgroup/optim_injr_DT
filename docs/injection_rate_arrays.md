# Injection Rate Arrays for DT Training

## Source

Values derived from bootstrap CDF analysis (`plots/bootstrap_cdf_analysis/grid_cdf_4x3.png`).

The ending rate for each case is **q_k\*** — the conservative bootstrap estimate (upper 95% CI band crossing at 1% fracture probability threshold, B=10000).

Each array has **length 6**, linearly spaced from `inj_start = 0.0001` to `q_k*`:

```
array = range(inj_start, q_k_star, length=6)   # Julia: 6 points inclusive
```

**Indexing (same dimension as optimization / bootstrap summaries):** the six entries are the six injection **periods**; the **last period** is **Julia index 6** (`rates[6]` / `rates[end]`) and **Python** `rates[-1]` or `rates[5]` in 0-based indexing. That last value equals **q_k\*** in the table below (before any visualization multiplier).

**`forward_sim_data.jld2` and `run_forward_export.jl`:** the forward simulator uses the **same ramps as this table** (no global multiplier). The last column of `fracture_comparison_3x3.png` is **`q_k\*` in m³/s**, directly comparable to the horizontal axis of the bootstrap CDF plots (`cdf_POF_eps0.png` / `cdf_POF_eps0.01.png` / CVaR case) for the matching risk setting.

## Injection Rate Arrays

### Case 1: POF ε=0.0 (q_k\* = 0.0263)

```
[0.00010, 0.00534, 0.01058, 0.01582, 0.02106, 0.02630]
```

### Case 2: POF ε=0.01 (q_k\* = 0.0453)

```
[0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530]
```

(Used for bootstrap `cdf_POF_eps0.01.png` and for the **middle column** of `fracture_comparison_3x3.png` — key `POF_eps0p01` in `forward_sim_data.jld2`.)

### Case 3: CVaR γ=0.1 α=0.01 (q_k\* = 0.0747)

```
[0.00010, 0.01502, 0.02994, 0.04486, 0.05978, 0.07470]
```

## Reference Values (all three crossing points from CDF plot)

| Case | q_k\* (conservative) | ECDF (median) | Opt (optimistic) |
|------|---------------------|---------------|-----------------|
| POF ε=0.0 | 0.0263 | 0.0275 | 0.0315 |
| POF ε=0.01 | 0.0453 | 0.047 | 0.056 |
| CVaR γ=0.1 α=0.01 | 0.0747 | 0.0764 | 0.0881 |

## Parameters

- `inj_start`: 0.0001 (from `optim_inject.jl` `--inj_start` default)
- Array length: 6
- Unit: m³/s
- Bootstrap: B=10000, 95% CI, seed=42
- Fracture probability threshold: 1%
- Number of geological samples: 128

---

# Step-2 Injection Rate Arrays for DT Training

## Source

Values derived from the step-2 paired posterior bootstrap comparison
(`plots/step2_paired_posterior_stats_casewise_counts/summary_grid_hist_cdf_casewise.png` and the corresponding single-case CDF figures).

For step 2, the ending rate for each case is again **q_k\***, the conservative bootstrap estimate
(upper 95% CI band crossing at the 1% fracture probability threshold, B=5000).

Each array has **length 6**, linearly spaced from the matching **step-1 q_k\*** to the new **step-2 q_k\***:

```
array = range(step1_q_k_star, step2_q_k_star, length=6)   # Julia: 6 points inclusive
```

This means the step-2 DT-training arrays start from the already-selected first monitoring step endpoint for the same risk case.

**Case-count note:** `POF eps=0.0` still uses `127` completed samples because sample `113` fractures even at zero injection rate and is intentionally excluded. `POF eps=0.01` and `CVaR gamma=0.1 alpha=0.01` use their full `128` completed samples.

## Injection Rate Arrays

### Step-2 Case 1: POF ε=0.0

- step-1 `q_k*`: `0.0263`
- step-2 `q_k*`: `0.0449` from `127` samples

```
[0.02630, 0.03002, 0.03373, 0.03745, 0.04117, 0.04489]
```

### Step-2 Case 2: POF ε=0.01

- step-1 `q_k*`: `0.0453`
- step-2 `q_k*`: `0.0732` from `128` samples

```
[0.04530, 0.05087, 0.05645, 0.06203, 0.06760, 0.07317]
```

### Step-2 Case 3: CVaR γ=0.1 α=0.01

- step-1 `q_k*`: `0.0747`
- step-2 `q_k*`: `0.1153` from `128` samples

```
[0.07470, 0.08282, 0.09094, 0.09906, 0.10717, 0.11529]
```

## Reference Values (all three crossing points from step-2 CDF plot)

| Case | q_k\* (conservative) | ECDF (median) | Opt (optimistic) |
|------|---------------------|---------------|-----------------|
| POF ε=0.0 | 0.0449 | 0.0481 | 0.0502 |
| POF ε=0.01 | 0.0732 | 0.0763 | 0.0788 |
| CVaR γ=0.1 α=0.01 | 0.1153 | 0.1199 | 0.1278 |

## Parameters

- step-2 array start: matching step-1 `q_k*` for the same risk case
- step-2 array end: step-2 conservative `q_k*`
- Array length: 6
- Unit: m³/s
- Bootstrap: B=5000, 95% CI, seed=42
- Fracture probability threshold: 1%
- Number of geological samples used per case: 127 for `POF eps=0.0`, 128 for the other two cases
