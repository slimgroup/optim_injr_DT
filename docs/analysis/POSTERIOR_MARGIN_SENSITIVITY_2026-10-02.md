# Relative-margin pressure sensitivity with a zero-aligned colorbar

The user requested a controlled amplification of pressure only for the relative
margin row, consistent amplification across the three cases, a colorbar matching
the pressure-limit comparison, and exceeding-cell annotations. After reviewing
the feasible choices, the user selected amplification of the **pressure increase**
rather than absolute pressure, and prioritized a small CVaR exceeding-cell count
even if PoF epsilon=0.01 remains without red cells.

This is a separate sensitivity preview. The unmodified posterior exports,
original JLD2 files, and injection-rate statistical figures are preserved.

## Transformation and scope

One common factor `s = 1.13` applies to every case, sample, grid cell, and
monitoring step k=1–4:

```text
pressure_used = pres_Hyd + 1.13 * (posterior_pressure - pres_Hyd)
p_max = pres_Hyd + 4e6 Pa
relative_margin_used = (p_max - pressure_used) / p_max
```

The transformation increases the pressure perturbation relative to the
hydrostatic reference by 13%; it does not multiply absolute pressure by 1.13.
Negative perturbations also follow the same affine formula, without clipping.
Only relative-margin calculations use `pressure_used`. The displayed pressure-
difference and saturation rows retain their original values and color limits.

The first row of the mean figure is the mean of the transformed relative
margin over 128 samples. The first row of the standard-deviation figure is
its population standard deviation (`ddof=0`). Since the transformation is
affine, `SD(relative_margin_used) = 1.13 * SD(original_relative_margin)` up to
the established float32 arithmetic. This is checked against float64 pressure
reductions independently for each case and step.

These transformed margins are **not** the original posterior estimates and
are **not** outputs of a new forward simulation or optimized control schedule.
The factor was selected as an exploratory visual sensitivity using the desired
cell-count scale. It is not a calibrated physical model parameter, and matching
the reference count does not constitute scientific validation. The original
state samples remain the numerical source and are never overwritten.

## Colorbar and counts

The mean-margin palette retains the reference's 26 Reds_r and 230 Blues entries
and the range `[-0.1, 1]`. The bin boundary is placed **exactly at r=0**, correcting
the old static figure's small positive red/blue transition. Every negative
value selects the red part of the palette; zero and positive values select
the nonnegative part. All cases and steps share this mapping. The std row
continues to use inferno, with one shared nonnegative range covering all steps.

The annotation is `Mean-field exceeding cells`: the number of grid cells where
the **mean transformed margin** is negative. It is not an ensemble failure
probability, a count of samples, or a count obtained by testing std values.
Per-sample exceeding-cell counts are recorded separately in `validation.json`.
No exceeding-cell annotation is attached to the standard-deviation maps.

The comparison source `cvar_day728_sensitivity_1p22x.jld2` contains 97 pressure-
exceeding cells in its single saved ground-truth field. That reference and the
posterior mean are different objects; the number 97 is used only as the user's
requested visual scale. It is not a probability or a target fit to observations.

The shared-factor constraint prevents simultaneously making PoF epsilon=0.01
red and retaining a CVaR count below 97. For example, the cached step-2 means
require approximately `s=1.4443` before PoF epsilon=0.01 begins to exceed; CVaR
then has roughly 4,484 exceeding cells. The chosen `s=1.13` keeps the response
modest and does not introduce separate per-case or per-step tuning.

## Reproduction and paper disclosure

```bash
sbatch scripts/shell/submit/submit_posterior_margin_sensitivity.sh \
  --mode increment --factor 1.13 \
  --output plots/paper_figures/posterior_margin_sensitivity_increment_1p13_20261002
```

Use a fresh output directory. The script verifies historical source hashes,
sample shapes, unchanged retained-row arrays/color maps/limits, affine mean/std
identities, the zero color boundary, annotation counts, and final-resolution
text bounds. It exports eight 400 dpi PNGs with distinct sensitivity filenames,
the displayed arrays, validation metadata, manifest, checksums, and code
snapshots. No PDF/SVG, optimization rerun, or bootstrap update is involved.

At the user's request, the amplification is not described inside the PNG.
It must accompany any paper use in the caption or methods. Suggested wording:

> The first row shows an illustrative pressure-sensitivity transformation of
> the posterior samples. For relative-margin calculations only, the pressure
> increment above the hydrostatic reference is multiplied by 1.13, using the
> same factor for all cases and monitoring steps. The pressure-difference and
> saturation rows remain unmodified. Red cells indicate negative mean
> transformed relative margin; annotated counts refer to grid cells of this
> mean field and are not ensemble failure probabilities. Standard deviations
> are computed across the transformed relative-margin samples.

Keep these files separate from the accepted unmodified posterior handoff.
Any manuscript path/caption switch must explicitly identify this sensitivity
interpretation; do not describe the new first row as unchanged posterior data.

## Completed preview

Slurm job `13819997` completed successfully in 1 minute 23 seconds. The eight
posterior PNGs are 6400 by 3388 pixels at 400 dpi. All stored checksums passed,
and the red-bin mask was verified to equal `mean(r_used) < 0` in all 12 mean
panels. The retained pressure-difference and saturation rows are exactly equal
to the historical plot arrays, including their color limits and colormaps.

| Step | PoF epsilon=0.0 cells | PoF epsilon=0.01 cells | CVaR cells | CVaR min(mean r_used) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0 | 0 | 0 | 0.017688 |
| 2 | 0 | 0 | 69 | -0.005180 |
| 3 | 0 | 0 | 0 | 0.005848 |
| 4 | 0 | 0 | 0 | 0.093281 |

The shared std range is `[0, 0.032]`. The annotation is intentionally omitted
from std maps because std is not a signed pressure margin.

A separate corrected reference PNG is generated under `reference_zero_aligned_v2/`
by `scripts/python_plots/preview_fracture_reference_zero_aligned.py`. It uses the
same exact-zero bin boundary as the posterior previews and retains all nine
original field arrays, their display limits, and the original exceeding-cell
counts `[0, 97, 6953]`. The reference's existing CVaR 1.22x schedule is retained;
the posterior-only 1.13 increment transformation is **not** applied to that
reference. This companion also preserves the old static annotations and must
retain their existing caption qualifications. The old reference PNG is not
overwritten.

The final companion was rendered by Slurm job `13820071` (8 seconds, exit 0)
with clean major ticks; its earlier draft remains in `reference_zero_aligned/`.
Use `reference_zero_aligned_v2/` for the reviewed reference copy.
