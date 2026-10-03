# Step-1 PoF ε=0.01: 1500-point versus observed-jump rendering

The user requested a PNG comparison before deciding whether to remove the
1500-point plotting grid from future ECDF figures. This task does not change
the existing production plotting functions or regenerate any case grid.

## Outputs

- [Side-by-side comparison](../../../plots/DT_control/exp_name=step1/statistical_analysis/ecdf/jump_comparison_20260916/comparison_POF_eps0.01.png)
- [Observed-jump single panel](../../../plots/DT_control/exp_name=step1/statistical_analysis/ecdf/jump_comparison_20260916/cdf_POF_eps0.01_observed_jumps.png)
- [Verification and input hashes](../../../plots/DT_control/exp_name=step1/statistical_analysis/ecdf/jump_comparison_20260916/verification.json)

Only PNG figures are exported. Existing images and numerical caches are unchanged.

## What the supplied single panel currently does

`labels_reviewed_v6_20260915/cdf_POF_eps0.01.png` draws its empirical CDF and
confidence band from **1500 evenly spaced x values**, connecting consecutive
values with straight segments. Its three marked rates already use **observed
sample jumps**, independent of that grid. Removing the plotting grid therefore
does not change the three markers in this particular source image.

The 128 original completed samples are preserved exactly. The plotted scalar
is the sixth element of the length-12 schedule, reconstructed from the final
nonzero endpoint using the case-level initial rate `0.0001 m³/s`. It is not
the twelfth schedule element. The 128 values contain **89 unique values**;
those values are the exact possible jump locations, rather than 128 equally
spaced evaluation points.

The left comparison panel reproduces the cached 1500-point numerical arrays
with the current line/fill drawing convention. The right panel evaluates and
draws the empirical CDF and both band edges at the 89 observed jumps, using
right-continuous `step(..., where="post")` and `fill_between(..., step="post")`.
Two display-boundary points extend the zero and one plateaus to the common
x limits; they do not participate in rate selection. Both panels have the
same limits, colors, target line, inset limits, marker values and labels.

The step rendering exposes vertical jumps in the tail inset in place of the
short sloping segments in the current figure. The overall distribution and
band are nearly indistinguishable at full scale. The old dense grid skips two
short plateau states, at rates `0.07580028409090911` and
`0.11386846590909092`, which the observed-jump version retains.

## Bootstrap and numerical verification

The frozen source is
`data/figure_exports/figures6_7_decimal4_20260910_005149/case_result.jld2`,
SHA-256 `287210f33be19644c1d87fd13cdb39f672afc345293315e834b690255251ecc3`.
Its 1500-point arrays cannot recover confidence values at the two skipped
states, so a new diagnostics export was created in
`data/figure_exports/pof_eps001_jump_comparison_20260916/`.

Slurm job **13248011** reran only the bootstrap calculation on the same cached
128 scalar values, using the same Julia `MersenneTwister(42)`, 10,000 resamples,
128 draws per resample, 95% pointwise interval and quantile arithmetic. No
optimization, posterior update or reservoir simulation was run. The job
finished successfully in 13 seconds.

Evaluating the new step functions at **all 1500 old grid locations** reproduces
the cached ECDF, lower band and upper band **exactly**, not just to display
precision. All three selected locations also match exactly:

| Marker | Full precision (m³/s) | Display |
| --- | ---: | ---: |
| Conservative, upper band | 0.045103409090909104 | 0.0451 |
| ECDF | 0.04677755681818183 | 0.0468 |
| Optimistic, lower band | 0.05583295454545456 | 0.0558 |

These are threshold boundaries. Stars are placed at 1% to identify the selected
x coordinates, not to assert that the corresponding step functions equal 1%.
At the first jump the upper band is `3/128 = 2.34375%`. The supplied
`Violation probability (%)` label is retained for comparison; the existing
caption's distinction between the endpoint ECDF and physical or strict
constraint-violation probabilities still applies.

Source PNG SHA-256 before and after:
`1740468b464a50511f677e2f6405116c1b70250f30230ba4f9a7b31ca9618b17`.
The new bootstrap output and original cache were also hash-checked before and
after rendering. Both main panels and their left-tail insets were visually
reviewed for clipping and annotation overlaps.

## Reproduction

```bash
sbatch scripts/shell/submit/submit_pof_jump_comparison.sh \
  data/figure_exports/figures6_7_decimal4_20260910_005149/case_result.jld2 \
  data/figure_exports/NEW_JUMP_DIAGNOSTICS

python scripts/python_plots/compare_pof_ecdf_observed_jumps.py \
  --jump-dir data/figure_exports/NEW_JUMP_DIAGNOSTICS \
  --outdir plots/DT_control/exp_name=step1/statistical_analysis/ecdf/NEW_COMPARISON
```

Both scripts refuse to replace an existing output directory. The batch entry
point activates the repository project and uses `$HOME/julia-depot`.

Recommendation: use observed jumps for both selection and step plotting in
future statistical exports, with the single and grid figures sharing the same
computed case results. This comparison is not a global switch of the existing
pipeline, and historical injection schedules remain unchanged.


## Follow-up: 2026-09-16

The user accepted observed-jump step plotting. The current pipeline no longer
uses the 1,500-point rendering grid; the three ECDF PNGs in the requested v6
folder now share exact jump-based statistics. This supersedes the rendering
recommendation above; historical audit/comparison artifacts remain unchanged.
See [the regeneration record](STEP1_ECDF_OBSERVED_JUMPS_2026-09-16.md).
