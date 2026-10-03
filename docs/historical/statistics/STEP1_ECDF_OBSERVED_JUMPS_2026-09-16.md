# Step-1 ECDFs on observed jumps — 2026-09-16

The user accepted the observed-jump comparison and requested re-rendering the
ECDF figures in `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v6_20260915`.
The single PoF ε=0.01, full 4×3, and selected 1×3 PNGs now share one computed
result per case. Only these three PNGs and their provenance are updated.
The three histograms are unchanged.

## Method and scope

- Read the same 128 completed `final.jld2` samples per case (all 12 cases).
  No missing-final candidates; the pre-submission user-job query was empty.
- Preserve the scalar: element 6 of the length-12 schedule reconstructed with
  `inj_start=0.0001` and the final nonzero endpoint in `inj_rate_arr[:, 1]`.
  The endpoint and element 6/12 are related by a fixed affine transformation;
  they are not separate statistical insights. The user requested retaining the
  original “Optimized-endpoint ECDF(s)” titles; the scalar remains element 6/12.
- Preserve 10,000 bootstrap resamples, MersenneTwister seed 42, pointwise 95%
  percentile bands, and the 1% threshold.
- Evaluate the ECDF and bootstrap bands at every sorted unique sample value.
  Render right-continuous `post` steps; two padded boundary points show the
  zero/one plateaus. There is no uniform 1,500-point evaluation grid.
- Derive all three crossings from those same arrays. `q_k*` is the first observed
  value whose upper CDF band is at least 1%; ECDF and optimistic use the empirical
  curve and lower band. This is a discrete crossing boundary, not a guarantee
  that the upper band stays below 1% at that value.
- Source optimization outputs and historical injection schedules are unchanged;
  no simulations or optimization were run. Grid annotation numbers change
  slightly because the old raster grids used grid-based crossings.
- PNG only; retain the original case colors, 0–8% insets, and 1% target line.

## Verification and values

The PoF ε=0.01 vector, bootstrap quantile samples, quantile summaries, and three
crossing values exactly match the frozen September 10 cache. Evaluating the new
steps at all 1,500 old grid positions exactly reproduces the original ECDF and
both band bounds. There are 89 unique jumps among its 128 samples.
Tied and constant sample checks also passed; Python step-2/3/4 helpers were
checked against independently evaluated bootstrap CDFs between sample jumps.

| Case | Samples | Unique jumps | q_k* (m³/s) | ECDF | Optimistic |
|---|---:|---:|---:|---:|---:|
| PoF ε=0.0 | 128 | 92 | 0.0261940568 | 0.0274369545 | 0.0314416477 |
| PoF ε=0.01 | 128 | 89 | 0.0451034091 | 0.0467775568 | 0.0558329545 |
| PoF ε=0.05 | 128 | 87 | 0.0814821023 | 0.0855659091 | 0.1083642045 |
| CVaR γ=0.0 α=0.0 | 128 | 92 | 0.0261940568 | 0.0274369545 | 0.0314416477 |
| CVaR γ=0.0 α=0.01 | 128 | 92 | 0.0261940568 | 0.0274369545 | 0.0314416477 |
| CVaR γ=0.0 α=0.05 | 128 | 92 | 0.0261940568 | 0.0274369545 | 0.0314416477 |
| CVaR γ=0.1 α=0.0 | 128 | 86 | 0.0451034091 | 0.0459024148 | 0.0526369318 |
| CVaR γ=0.1 α=0.01 | 128 | 88 | 0.0742022727 | 0.0759778409 | 0.0876965909 |
| CVaR γ=0.1 α=0.05 | 128 | 90 | 0.0980659091 | 0.1009068182 | 0.1222136364 |
| CVaR γ=0.2 α=0.0 | 128 | 80 | 0.0624977273 | 0.0703102273 | 0.0751681818 |
| CVaR γ=0.2 α=0.01 | 128 | 87 | 0.1108500000 | 0.1151113636 | 0.1321568182 |
| CVaR γ=0.2 α=0.05 | 128 | 91 | 0.1492022727 | 0.1506227273 | 0.1847136364 |

## Sources and reproduction

- Production plotter: `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`.
- Focused exporter: `scripts/julia_scripts/plotting/bootstrap_ecdf/reexport_step1_ecdf_jumps.jl`.
- New full-precision cache and verification: `data/figure_exports/step1_ecdf_observed_jumps_20260916/`.
- Frozen PoF reference: `data/figure_exports/figures6_7_decimal4_20260910_005149/case_result.jld2`.
- Statistics job: 13248189; final cached-layout rendering job: 13248294 (13248254 was a layout review).
- Future Julia step-2 dual-prior and Python step-2/3/4 paired-posterior plotters
  also use observed jumps and stepped bands; their existing PNGs are untouched.
  The deprecated `npts` argument remains accepted for caller compatibility,
  but cannot change the sampling. Frozen historical exporters retain their
  existing parameter guards and are not silently migrated.

```bash
sbatch scripts/shell/submit/submit_step1_ecdf_jumps.sh NEW_PLOT_DIR NEW_CACHE_DIR
# To adjust layout without repeating statistics:
sbatch scripts/shell/submit/submit_step1_ecdf_jumps.sh ANOTHER_NEW_PLOT_DIR EXISTING_CACHE_DIR --render-only
```

Both modes refuse to replace an existing plot directory. Installation into the
requested reviewed folder replaces only its three specifically requested ECDF
PNGs. Pre-update metadata is retained with the numerical cache for provenance.

Final visual review passed for all three PNGs. SHA-256 checks confirm that all
three histogram PNGs are byte-for-byte unchanged. Current PNG checksums and
case values are recorded in the reviewed folder’s `manifest.json` and
`observed_jump_update_verification.json`.

## User title correction

The user requested restoring the original title on all three figures. The single
figure uses `Optimized-endpoint ECDF (PoF ε = 0.01)`; both grids use
`Optimized-endpoint ECDFs`. The added monitoring-step / initial-ensemble subtitle
is removed, and the original title font sizes and header spacing are restored.
Job 13249005 renders from the same saved case results using `--render-only`;
the observed-jump method and all numerical values remain unchanged.

## Histogram q_k* alignment

The user subsequently identified the stale grid-based q_k* labels in the two
histogram grids. Job 13249808 rendered only `grid_histogram_4x3.png` and
`grid_histogram_selected_1x3.png` from the same saved case results, updating
both the red dashed line coordinates and their four-decimal legend values.
The original titles, sample inclusion, 30 shared histogram bins, and quantile
calculation are retained. No bootstrap, optimization or simulations were rerun.

The selected cases change as follows (m³/s):

| Case | Old displayed q_k* | Observed-jump q_k* |
|---|---:|---:|
| PoF ε=0.0 | 0.0263 | 0.0262 |
| PoF ε=0.01 | 0.0453 | 0.0451 |
| CVaR γ=0.1, α=0.01 | 0.0747 | 0.0742 |

All 12 cases in the full grid now match the ECDF case-result cache. The single
PoF histogram was already correct (`q_k*=0.0451`) and remains byte-for-byte
unchanged, as do all three ECDF PNGs and the numerical cache.

The green 1% sample quantile remains 0.04831164772727274 (displayed 0.0483).
Julia's default interpolated sample quantile places it 27% of the way from
order statistic 2 to order statistic 3 for n=128. It is distinct from the
ECDF inverse crossing (0.04677755681818183) and upper-band crossing
(0.045103409090909104); removal of the plotting grid does not change it.

The full-grid CVaR γ=0.2, α=0.01 minimum is now consistently formatted from
its original full-precision value 0.11085 using `Printf` as 0.1109 (previous
raster 0.1108). This is a rounding-display change, not a changed sample.
The same value is also the new q_k* in that case.

Verification records are `histogram_verification.toml` beside the numerical
cache and `histogram_q_update_verification.json` in the reviewed folder.
Historical metadata before this histogram update is retained beside the cache.

```bash
sbatch scripts/shell/submit/submit_step1_ecdf_jumps.sh NEW_PLOT_DIR EXISTING_CACHE_DIR --histograms-only
```
