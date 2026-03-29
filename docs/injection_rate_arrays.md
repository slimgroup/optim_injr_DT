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
