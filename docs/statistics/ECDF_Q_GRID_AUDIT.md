# Audit of the bootstrap-ECDF q grid

## Conclusion

The 1,500-point grid was not plotting-only.  All five scripts that define
`ECDF_PTS = 1500` also used the first dense-grid location at which the upper
pointwise bootstrap CDF band reached 1% as the displayed `q_k*`; the primary
campaign values were subsequently documented and reused. Consequently, the
selected rate depended on the arbitrary grid resolution and alignment.

The direct crossing is well defined for every audited case.  The selection code
now evaluates the upper bootstrap CDF band on the sorted unique observed
optimized rates and uses that crossing for `q_k*`; the 1,500-point grid is
retained only to draw the CDF and confidence band.  The audit and updated code
use `B = 10,000`, a 95% pointwise interval, threshold 0.01, and seed 42.

At the 1% threshold and the available sample sizes, the upper band already
exceeds 1% at the smallest completed-sample rate.  The direct `q_k*` is therefore
the observed minimum in every audited case.  The upper-band value at that jump
is 3/128 = 2.34375% for the 128-sample cases, 3/127 = 2.36220%,
3/124 = 2.41935%, 3/122 = 2.45902%, and 3/32 = 9.375% for the exploratory
32-sample comparison.  Thus the direct crossing is an actual ECDF jump rather
than an interpolated value.

There is a discrete-decision nuance worth stating in the paper. Under the
repository's existing “first point with upper CDF >= 1%” convention, `q_k*` is
the boundary where the upper band jumps past 1%; it is not an observed rate at
which the upper band equals or remains below 1%. In fact, no observed endpoint
satisfies `upper CDF <= 1%` in these samples. The safe set under a strict
upper-band rule is the interval below the observed minimum, whose supremum is
that minimum. Accordingly, the reported direct value should be described as a
conservative threshold boundary.

## Locations and prior behavior

| File | Analysis covered | How 1,500 points affected selection before the change |
|---|---|---|
| `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl` | Step 1, 12-case grid plus the additional CVaR gamma=0.05, alpha=0.05 single panel | `compute_case` applied `threshold_crossing` to the grid-evaluated upper band. |
| `scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl` | Step-2 exploratory 32-sample dual-prior comparison | `build_case_stats` selected `x_cons` from the grid-evaluated upper band. |
| `scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py` | Step-2 paired posterior, 3 primary cases | Both the single and grid plot functions calculated the displayed `q_k*` from the grid. |
| `scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py` | Step-3 paired posterior, 3 primary cases | Both the single and grid plot functions calculated the displayed `q_k*` from the grid. |
| `scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py` | Step-4 paired posterior, 3 primary cases | Both the single and grid plot functions calculated the displayed `q_k*` from the grid. |

No other `ECDF_PTS = 1500` definitions were found in the repository.  The step-2
through step-4 Python scripts and the exploratory step-2 Julia script actually
used `B = 5,000` before this audit, despite the requested/common methodology of
`B = 10,000`; they have now been standardized to 10,000 without changing seed 42.

The historical Julia ECDF helper counted observations strictly below a grid
location.  It now uses the standard right-continuous definition
`F_n(q) = count(x_i <= q) / n`, matching the Python scripts and making observed
endpoints true jump locations.

## Grid spacing and sensitivity

Each historical grid spans the data range plus a 5% margin at each end.  If
`R = max(q) - min(q)`, its exact spacing is

```text
Delta q_grid = 1.10 R / (N_grid - 1).
```

The table gives the range of spacings across all 26 audited analyses and the
largest change from the grid-selected value to the direct jump-selected value.
Relative change is `abs(q_direct - q_grid) / abs(q_grid)`.

| Grid points | Spacing range (m^3/s) | Maximum absolute change (m^3/s) | Maximum relative change |
|---:|---:|---:|---:|
| 250 | 7.75589e-4 to 4.41140e-3 | 3.00777e-3 | 3.116% |
| 500 | 3.87017e-4 to 2.20128e-3 | 7.00406e-4 | 0.743% |
| 1,000 | 1.93315e-4 to 1.09954e-3 | 6.49726e-4 | 0.690% |
| 1,500 | 1.28834e-4 to 7.32780e-4 | 6.32856e-4 | 0.672% |
| 3,000 | 6.43953e-5 to 3.66268e-4 | 2.49728e-4 | 0.266% |
| 6,000 | 3.21923e-5 to 1.83103e-4 | 5.82602e-5 | 0.062% |

The error is not guaranteed to decrease monotonically for an individual case,
because it depends on where an observed jump falls relative to the padded grid.
A 500-point grid is adequate for drawing these panels but should not be used for
rate selection.

Exact per-case values for all six grid sizes, including each case's spacing and
signed/absolute/relative changes both against the direct crossing and against
the historical 1,500-point result, are in
[`ecdf_q_grid_audit.csv`](ecdf_q_grid_audit.csv).  The CSV has 156 rows:
26 analyses times 6 grid sizes.

## Old versus new `q_k*`

“Old” is the recomputed 1,500-point-grid crossing; “new” is the crossing on
sorted unique observed schedule-element-6/12 values.  Values are in m^3/s.

| Step | Scope | Case | n | Old: 1,500 grid | New: direct jump | Absolute change | Relative change |
|---|---|---|---:|---:|---:|---:|---:|
| step 1 | primary | PoF eps=0.0 | 128 | 0.02630532 | 0.02619406 | 0.00011127 | 0.423% |
| step 1 | primary | PoF eps=0.01 | 128 | 0.04530892 | 0.04510341 | 0.00020551 | 0.454% |
| step 1 | primary | PoF eps=0.05 | 128 | 0.08190941 | 0.08148210 | 0.00042731 | 0.522% |
| step 1 | primary | CVaR gamma=0.0 alpha=0.0 | 128 | 0.02630532 | 0.02619406 | 0.00011127 | 0.423% |
| step 1 | primary | CVaR gamma=0.0 alpha=0.01 | 128 | 0.02630532 | 0.02619406 | 0.00011127 | 0.423% |
| step 1 | primary | CVaR gamma=0.0 alpha=0.05 | 128 | 0.02630532 | 0.02619406 | 0.00011127 | 0.423% |
| step 1 | primary | CVaR gamma=0.1 alpha=0.0 | 128 | 0.04534177 | 0.04510341 | 0.00023837 | 0.526% |
| step 1 | primary | CVaR gamma=0.1 alpha=0.01 | 128 | 0.07470442 | 0.07420227 | 0.00050214 | 0.672% |
| step 1 | primary | CVaR gamma=0.1 alpha=0.05 | 128 | 0.09869876 | 0.09806591 | 0.00063286 | 0.641% |
| step 1 | primary | CVaR gamma=0.2 alpha=0.0 | 128 | 0.06283985 | 0.06249773 | 0.00034212 | 0.544% |
| step 1 | primary | CVaR gamma=0.2 alpha=0.01 | 128 | 0.11147475 | 0.11085000 | 0.00062475 | 0.560% |
| step 1 | primary | CVaR gamma=0.2 alpha=0.05 | 128 | 0.14980272 | 0.14920227 | 0.00060045 | 0.401% |
| step 1 | additional single | CVaR gamma=0.05 alpha=0.05 | 128 | 0.07676353 | 0.07633295 | 0.00043058 | 0.561% |
| step 2 | primary paired | PoF eps=0.0 | 127 | 0.04488686 | 0.04473886 | 0.00014800 | 0.330% |
| step 2 | primary paired | PoF eps=0.01 | 128 | 0.07316551 | 0.07289375 | 0.00027176 | 0.371% |
| step 2 | primary paired | CVaR gamma=0.1 alpha=0.01 | 128 | 0.11529273 | 0.11489318 | 0.00039955 | 0.347% |
| step 3 | primary paired | PoF eps=0.0 | 124 | 0.06201332 | 0.06186131 | 0.00015201 | 0.245% |
| step 3 | primary paired | PoF eps=0.01 | 128 | 0.08022973 | 0.07995011 | 0.00027962 | 0.349% |
| step 3 | primary paired | CVaR gamma=0.1 alpha=0.01 | 128 | 0.11865792 | 0.11813119 | 0.00052673 | 0.444% |
| step 4 | primary paired | PoF eps=0.0 | 122 | 0.07323323 | 0.07306384 | 0.00016940 | 0.231% |
| step 4 | primary paired | PoF eps=0.01 | 128 | 0.08114201 | 0.08087134 | 0.00027067 | 0.334% |
| step 4 | primary paired | CVaR gamma=0.1 alpha=0.01 | 128 | 0.12022143 | 0.11979182 | 0.00042961 | 0.357% |
| step 2 | dual-prior, 32 | PoF eps=0.01, pointwise median | 32 | 0.07310069 | 0.07289375 | 0.00020694 | 0.283% |
| step 2 | dual-prior, 32 | CVaR gamma=0.1 alpha=0.01, pointwise median | 32 | 0.12232566 | 0.12199545 | 0.00033020 | 0.270% |
| step 2 | dual-prior, 32 | PoF eps=0.01, paired posterior | 32 | 0.07310069 | 0.07289375 | 0.00020694 | 0.283% |
| step 2 | dual-prior, 32 | CVaR gamma=0.1 alpha=0.01, paired posterior | 32 | 0.12520913 | 0.12488075 | 0.00032837 | 0.262% |

The step-1 PoF eps=0.0 and all three CVaR gamma=0.0 cases contain exactly the
same 128 plotted values.  Their identical statistics are mathematically
redundant and are retained above only to document every parameter-grid cell.

## Reproducibility and historical campaign inputs

The audit reads only completed samples with `final.jld2` and reconstructs the
6th element of each length-12 optimized schedule using the case-level
`inj_start`, exactly as the monitoring-step plotting scripts do.  It does not
treat missing/no-final samples as zero or as missing at random.

The already-run monitoring campaigns used the rounded, grid-based values recorded
in `docs/injection_rate_arrays.md` as the next step's `inj_start`.  Those
historical arrays were not retroactively changed by this audit; changing them
would misstate the inputs that generated the existing step-2 through step-4
results.  The direct values above are the corrected `q_k*` estimates to report
from the statistical analyses and to use for future selections.

## Files changed by the audit

- `scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`
- `scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl`
- `scripts/python_plots/posterior_stats/plot_step2_paired_posterior_stats.py`
- `scripts/python_plots/posterior_stats/plot_step3_paired_posterior_stats.py`
- `scripts/python_plots/posterior_stats/plot_step4_paired_posterior_stats.py`
- `scripts/python_tools/analysis/audit_ecdf_q_grid.py`
- `docs/statistics/ecdf_q_grid_audit.csv`
- `docs/statistics/ECDF_Q_GRID_AUDIT.md`
- `docs/statistics/BOOTSTRAP_CDF_METHODOLOGY.md`
- `docs/injection_rate_arrays.md`

During the Julia helper validation, the step-1 entry point was inadvertently
invoked before the test was interrupted.  It regenerated (and therefore
overwrote) these eight existing single-panel outputs using the new jump-based
crossings; no grid figures or optimization/posterior artifacts were overwritten:

- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/hist_POF_eps0.01.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/cdf_POF_eps0.01.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/hist_CVaR_g0.05_a0.05.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/cdf_CVaR_g0.05_a0.05.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/hist_POF_eps0.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/cdf_POF_eps0.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/hist_CVaR_g0.1_a0.01.png`
- `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/cdf_CVaR_g0.1_a0.01.png`


## Follow-up: 2026-09-16

The user accepted observed-jump step plotting. The current pipeline no longer
uses the 1,500-point rendering grid; the three ECDF PNGs in the requested v6
folder now share exact jump-based statistics. This supersedes the rendering
recommendation above; historical audit/comparison artifacts remain unchanged.
See [the regeneration record](../historical/statistics/STEP1_ECDF_OBSERVED_JUMPS_2026-09-16.md).
