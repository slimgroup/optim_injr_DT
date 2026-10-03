# Injection Rate Arrays for DT Training

> Historical-input note: the arrays below preserve the rounded, 1,500-point-grid
> selections actually used to initialize the completed monitoring campaigns.
> They are not retroactively replaced by the direct ECDF-jump values, because
> doing so would misstate the inputs that produced the existing results. The
> corrected statistical `q_k*` values for paper reporting and future selections
> are listed in [`statistics/ECDF_Q_GRID_AUDIT.md`](statistics/ECDF_Q_GRID_AUDIT.md).

## Source

Values derived from the first monitoring-step bootstrap CDF analysis
(`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/grid_cdf_4x3.png` and the matching single-case CDF figures).

For step 1, the ending rate for each case is **q_k\*** — the conservative statistical-analysis
estimate (upper 95% CI band crossing at the 1% fracture probability threshold, `B=10000`).
In this repository, `q_k*` means the value selected directly from the monitoring-step
statistical analysis; it is not a separately back-solved quantity.

Because the first monitoring step has no previous monitoring-step campaign, the step-1
DT-training arrays start from the global optimization lower bound `inj_start = 0.0001`
and end at the step-1 `q_k*` selected from the bootstrap CDF analysis.

Each array has **length 6**, linearly spaced from `inj_start = 0.0001` to `q_k*`:

```
array = range(inj_start, q_k_star, length=6)   # Julia: 6 points inclusive
```

**Indexing (same dimension as optimization / bootstrap summaries):** the six entries are the six injection **periods**; the **last period** is **Julia index 6** (`rates[6]` / `rates[end]`) and **Python** `rates[-1]` or `rates[5]` in 0-based indexing. That last value equals the step-1 **q_k\*** in the table below.

**`forward_sim_data.jld2` and `run_forward_export.jl`:** the forward simulator uses the **same ramps as this table** (no global multiplier). The last column of `fracture_comparison_3x3.png` is **`q_k\*` in m³/s**, directly comparable to the horizontal axis of the bootstrap CDF plots (`cdf_POF_eps0.png` / `cdf_POF_eps0.01.png` / CVaR case) for the matching risk setting.

**Representative-case note:** this section records the three representative risk cases that are
carried forward through the later monitoring steps:
`PoF ε=0.0`, `PoF ε=0.01`, and `CVaR γ=0.1 α=0.01`.

## Injection Rate Arrays

### Case 1: PoF ε=0.0 (q_k\* = 0.0263)

```
[0.00010, 0.00534, 0.01058, 0.01582, 0.02106, 0.02630]
```

### Case 2: PoF ε=0.01 (q_k\* = 0.0453)

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
| PoF ε=0.0 | 0.0263 | 0.0275 | 0.0315 |
| PoF ε=0.01 | 0.0453 | 0.047 | 0.056 |
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
(`plots/step2_paired_posterior_stats/summary_grid_hist_cdf.png` and the corresponding single-case CDF figures).

For step 2, the ending rate for each case is again **q_k\***, the conservative bootstrap estimate
(upper 95% CI band crossing at the 1% fracture probability threshold; the
historical run used B=5000, while the audited code now uses B=10000).

Each array has **length 6**, linearly spaced from the matching **step-1 q_k\*** to the new **step-2 q_k\***:

```
array = range(step1_q_k_star, step2_q_k_star, length=6)   # Julia: 6 points inclusive
```

This means the step-2 DT-training arrays start from the already-selected first monitoring step endpoint for the same risk case.

**Case-count note:** `PoF eps=0.0` still uses `127` completed samples because sample `113` fractures even at zero injection rate and is intentionally excluded. `PoF eps=0.01` and `CVaR gamma=0.1 alpha=0.01` use their full `128` completed samples.

## Injection Rate Arrays

### Step-2 Case 1: PoF ε=0.0

- step-1 `q_k*`: `0.0263`
- step-2 `q_k*`: `0.0449` from `127` samples

```
[0.02630, 0.03002, 0.03373, 0.03745, 0.04117, 0.04489]
```

### Step-2 Case 2: PoF ε=0.01

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
| PoF ε=0.0 | 0.0449 | 0.0481 | 0.0502 |
| PoF ε=0.01 | 0.0732 | 0.0763 | 0.0788 |
| CVaR γ=0.1 α=0.01 | 0.1153 | 0.1199 | 0.1278 |

## Parameters

- step-2 array start: matching step-1 `q_k*` for the same risk case
- step-2 array end: step-2 conservative `q_k*`
- Array length: 6
- Unit: m³/s
- Bootstrap: historical run B=5000; audited code B=10000; 95% CI; seed=42
- Fracture probability threshold: 1%
- Number of geological samples used per case: 127 for `PoF eps=0.0`, 128 for the other two cases

---

# Step-3 Injection Rate Arrays for DT Training

## Source

Values derived from the final step-3 paired posterior statistical analysis
([summary_grid_hist_cdf.png](../plots/step3_paired_posterior_stats/summary_grid_hist_cdf.png)
and the corresponding single-case histogram / CDF figures under
`plots/step3_paired_posterior_stats/`).

For step 3, the ending rate for each case is again **q_k\***, the conservative bootstrap estimate
(upper 95% CI band crossing at the 1% fracture probability threshold; the
historical run used B=5000, while the audited code now uses B=10000).

Each array has **length 6**, linearly spaced from the matching **step-2 q_k\*** to the new **step-3 q_k\***:

```
array = range(step2_q_k_star, step3_q_k_star, length=6)   # Julia: 6 points inclusive
```

This means the step-3 DT-training arrays start from the already-selected second monitoring step endpoint for the same risk case.

**Case-count note:** step 3 does **not** use all 128 realizations for `PoF eps=0.0`. Samples `11`, `43`, `54`, and `117`
hit `first_forward failed even at minimum injection rate 0.0001`, so they are treated as strong infeasible / fracture candidates
and excluded from the histogram / CDF fit. The other two cases use their full `128` completed samples.

## Injection Rate Arrays

### Step-3 Case 1: PoF ε=0.0

- step-2 `q_k*`: `0.04489`
- step-3 `q_k*`: `0.06201` from `124` completed samples
- excluded infeasible / fracture candidates: `11, 43, 54, 117`

```
[0.04489, 0.04831, 0.05174, 0.05516, 0.05859, 0.06201]
```

### Step-3 Case 2: PoF ε=0.01

- step-2 `q_k*`: `0.07317`
- step-3 `q_k*`: `0.08023` from `128` completed samples

```
[0.07317, 0.07458, 0.07599, 0.07741, 0.07882, 0.08023]
```

### Step-3 Case 3: CVaR γ=0.1 α=0.01

- step-2 `q_k*`: `0.11529`
- step-3 `q_k*`: `0.11866` from `128` completed samples

```
[0.11529, 0.11596, 0.11664, 0.11731, 0.11798, 0.11866]
```

## Reference Values (all three crossing points from step-3 CDF plot)

| Case | q_k\* (conservative) | ECDF (median) | Opt (optimistic) |
|------|---------------------|---------------|-----------------|
| PoF ε=0.0 | 0.06201 | 0.06254 | 0.07187 |
| PoF ε=0.01 | 0.08023 | 0.08088 | 0.10160 |
| CVaR γ=0.1 α=0.01 | 0.11866 | 0.11927 | 0.16562 |

## Parameters

- step-3 array start: matching step-2 `q_k*` for the same risk case
- step-3 array end: step-3 conservative `q_k*`
- Array length: 6
- Unit: m³/s
- Bootstrap: historical run B=5000; audited code B=10000; 95% CI; seed=42
- Fracture probability threshold: 1%
- Number of geological samples used per case: `124` for `PoF eps=0.0`, `128` for the other two cases
- Step-3 infeasible / fracture candidates under `PoF eps=0.0`: `11, 43, 54, 117`

---

# Step-4 Injection Rate Arrays for DT Training

## Source

Values derived from the final step-4 paired posterior statistical analysis
([summary_grid_hist_cdf.png](../plots/step4_paired_posterior_stats/summary_grid_hist_cdf.png)
and the corresponding single-case histogram / CDF figures under
`plots/step4_paired_posterior_stats/`).

For step 4, the plotted scalar in the statistical analysis is again the **6th element of the
length-12 optimized injection-rate array**, reconstructed from the saved `inj_rate_arr`
endpoint and the matching step-3 `inj_start`.

Following the existing project convention, the `q_k*` values documented below are taken
directly from that statistical analysis scale. In other words, the step-4 `q_k*` listed
here is exactly the conservative crossing value shown in
`plots/step4_paired_posterior_stats/summary_grid_hist_cdf.png`.

Each array has **length 6**, linearly spaced from the matching **step-3 `q_k*`** to the new
**step-4 `q_k*`**:

```
array = range(step3_q_k_star, step4_q_k_star, length=6)   # Julia: 6 points inclusive
```

This means the step-4 DT-training arrays start from the already-selected third monitoring
step endpoint for the same risk case.

**Case-count note:** step 4 again does **not** use all 128 realizations for `PoF eps=0.0`.
Samples `5`, `16`, `28`, `36`, `47`, and `117` hit
`first_forward failed even at minimum injection rate 0.0001`, so they are treated as strong
infeasible / fracture candidates and excluded from the histogram / CDF fit. The other two
cases use their full `128` completed samples.

## Injection Rate Arrays

### Step-4 Case 1: PoF ε=0.0

- step-3 `q_k*`: `0.06201`
- step-4 `q_k*`: `0.07323` from `122` completed samples
- excluded infeasible / fracture candidates: `5, 16, 28, 36, 47, 117`

```
[0.06201, 0.06425, 0.06650, 0.06874, 0.07099, 0.07323]
```

### Step-4 Case 2: PoF ε=0.01

- step-3 `q_k*`: `0.08023`
- step-4 `q_k*`: `0.08114` from `128` completed samples

```
[0.08023, 0.08041, 0.08059, 0.08078, 0.08096, 0.08114]
```

### Step-4 Case 3: CVaR γ=0.1 α=0.01

- step-3 `q_k*`: `0.11866`
- step-4 `q_k*`: `0.12022` from `128` completed samples

```
[0.11866, 0.11897, 0.11928, 0.11960, 0.11991, 0.12022]
```

## Reference Values (all three crossing points from the step-4 CDF plot)

| Case | q_k\* (conservative) | ECDF (median) | Opt (optimistic) |
|------|---------------------|---------------|-----------------|
| PoF ε=0.0 | 0.07323 | 0.07519 | 0.07912 |
| PoF ε=0.01 | 0.08114 | 0.08396 | 0.10120 |
| CVaR γ=0.1 α=0.01 | 0.12022 | 0.12619 | 0.14360 |

## Parameters

- step-4 array start: matching step-3 `q_k*` for the same risk case
- step-4 array end: step-4 conservative `q_k*`
- Array length: 6
- Unit: m³/s
- Bootstrap: historical run B=5000; audited code B=10000; 95% CI; seed=42
- Fracture probability threshold: 1%
- Number of geological samples used per case: `122` for `PoF eps=0.0`, `128` for the other two cases
- Step-4 infeasible / fracture candidates under `PoF eps=0.0`: `5, 16, 28, 36, 47, 117`
