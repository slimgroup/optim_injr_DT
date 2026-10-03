# Figures 6--7: decimal formatting only (2026-09-09)

Updated 2026-09-10: the user changed the requested rate precision to **four
decimal places**, replacing the original five-decimal request. The source was
confirmed under `scripts/julia_scripts/plotting/bootstrap_ecdf/`.

Updated authorization, 2026-09-10: the user approved recomputing the figure
statistics from existing `final.jld2` files and requested backups of the old
images. This supersedes the original prohibition on recomputing statistics.
Optimization and forward simulations remain outside this task.

Status: **completed**. Slurm job `13050868` exported exactly two new PNG figures
using the four-decimal formatting. All 128
original samples have `final.jld2`; no optimization sample jobs are active.
The original images are unchanged and have verified, byte-identical backups in
`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/decimal4_20260910_005149/originals/`.
The new images are in that run directory, alongside `originals/`:

- `hist_POF_eps0.01.png` (1580 × 1180 pixels, 200 DPI)
- `cdf_POF_eps0.01.png` (1600 × 1201 pixels, 200 DPI)

Validation: the dimensions, DPI and Matplotlib version (3.7.1) match the old
exports. Outside the histogram legend and the rate tick-label regions, both
images are pixel-identical to their originals. The histogram bars, CDF curves,
bootstrap bands, marker positions, titles, units and probability labels are
therefore unchanged in the exported images. Visual inspection found no clipped
or overlapping text. The ECDF was also checked directly against the 128 loaded
sample values. Original and backup checksums match.

The run directory contains `verification.json`, `backup_checksums.json` and
`before_after_rate_labels.csv`. Only the requested two figures were re-exported.

The requested originals are:

- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/hist_POF_eps0.01.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/cdf_POF_eps0.01.png`

Their SHA-256 checksums at intake were, respectively:

```text
91b839992601742314891a28db0a23b55fed4d13f596ecb9c091655470318c1a
4c7f843c6eada61b4dad7e9ddc5e65df3f76103990a8b70b8feb7fa02eb15110
```

The lowercase paper-facing copies in `plots/paper_figures/statistical/` are
different files and were also left untouched.

## Code change

In `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`,
`plot_single_hist` and `plot_single_cdf` now accept `four_decimal_rates=true`.
This applies `%.4f` to rate annotations, the existing histogram summary, and
the rate ticks on both main axes and the CDF inset. It preserves trailing zeros
and leaves tick locations, axis titles, probability labels, units, marker
coordinates, bins, curves, layout, and export settings in place. The
`run_part1_only!` entry point enables this option for `POF_eps0.01` only; other
cases and grid plots retain their original formatting.

`BOOTSTRAP_DEFINE_ONLY=1` permits loading the definitions without invoking the
data collection or statistical pipeline. A saved, full-precision `CaseResult`
can then be passed directly to these two functions, with new output paths.
The dedicated `reexport_figures_6_7.jl` now calls `compute_case` under the updated
authorization and caches its complete result under
`data/figure_exports/figures6_7_decimal4_20260910_005149/` for future formatting
changes without recomputation. It only exports the requested histogram and CDF.

## Reason recomputation was needed

The existing script computes `CaseResult` in memory, writes PNG images, and does
not serialize that result. No matching saved plot object or complete numerical
cache was located in the figure folder or the checked repository artifacts.
The located raw-sample aggregate CSVs are not a saved result for these figures.
The PNG metadata contains the rendering software and DPI, not numerical results.

The authorized recomputation uses the existing script's sample extractor,
quantile and bootstrap functions. The new cache includes sample values, selected
quantile and crossing values, plotting grid, ECDF and bootstrap-band arrays,
bootstrap count and sample paths. No digits are inferred from raster labels.

## Before/after rate labels

The new strings are formatted directly from recomputed full-precision values.
Every recomputed annotation matches the original at its previous display
precision. The 1% quantile is `0.04831164772727274`, and the selected rate is
`0.045103409090909104`; they are kept as separate existing quantities.

| Figure | Rate label | Before | After |
|---|---|---|---|
| 6 | 1% quantile | `0.04831` | `0.0483` |
| 6 | selected rate | `0.0451` | `0.0451` |
| 6 | mean | `0.1279` | `0.1279` |
| 6 | standard deviation | `0.0689` | `0.0689` |
| 6 | minimum | `0.0451` | `0.0451` |
| 6 | maximum | `0.3694` | `0.3694` |
| 7 | selected-rate crossing | `0.0451` | `0.0451` |
| 7 | ECDF crossing | `0.0468` | `0.0468` |
| 7 | optimistic crossing | `0.0558` | `0.0558` |

Both main rate axes now show four decimal places at the same tick positions:
`0.05` through `0.35` become `0.0500` through `0.3500` (spacing 0.05).
The CDF inset ticks `0.040`, `0.045`, `0.050`, `0.055`, `0.060` become
`0.0400`, `0.0450`, `0.0500`, `0.0550`, `0.0600`.

The deferred label/statistical-definition audit was not performed. Pre-existing
working-tree changes were preserved. No commit was created.
