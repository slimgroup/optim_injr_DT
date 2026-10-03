# Relative-margin sensitivity preview with a 200-cell ceiling

The user requested a slightly larger pressure-increment transformation than
the prior 1.13 preview, allowing up to 200 CVaR mean-field exceeding cells.
The new preview uses one common factor **1.145** for all three cases, all four
monitoring steps, and all 128 samples:

```text
p_used = pres_Hyd + 1.145 * (p - pres_Hyd)
p_max = pres_Hyd + 4e6 Pa
r_used = (p_max - p_used) / p_max
```

This is a 14.5% increase of the hydrostatic-reference pressure increment,
compared with 13% in the previous preview. It is applied only to relative-margin
calculations. Mean and population standard deviation (`ddof=0`) are computed
from the transformed margin samples. Pressure-difference and saturation rows
retain the original arrays, colormaps, and limits. Original data, prior artwork,
and statistical rate results remain unchanged.

The factor is an exploratory sensitivity choice guided by the user's requested
count scale, not a fitted physical parameter or a new simulation result.
`Mean-field exceeding cells` counts cells where the transformed posterior
mean margin is negative; it is not a count of samples or a failure probability.
The count constraint applies to the CVaR mean field at every monitoring step.
Only relative-margin means use the sign-sensitive red/blue palette; std uses
the shared nonnegative inferno scale.

The exact-zero red/blue boundary and mean color limits `[-0.1, 1]` remain those
of the preceding zero-aligned preview. The corrected day-728 reference is
unchanged and remains in
`plots/paper_figures/posterior_margin_sensitivity_increment_1p13_20261002/reference_zero_aligned_v2/`.

## Reproduction

```bash
sbatch scripts/shell/submit/submit_posterior_margin_sensitivity.sh \
  --mode increment --factor 1.145 \
  --output plots/paper_figures/posterior_margin_sensitivity_increment_1p145_20261002
```

The existing renderer and Slurm entry point are reused without code changes.
Outputs are eight 400 dpi PNGs with distinct sensitivity filenames, numerical
arrays, validation metadata, source snapshots, and checksums. The old 1.13
preview is retained. The multiplier is deliberately documented outside the
PNG, in accordance with the user's request; paper captions/methods must explain
the transformation, identify the first row as a sensitivity illustration,
and state that the other two rows are unmodified.

Use 1.145 in the disclosure text for these new files. Do not reuse the prior
1.13 caption verbatim or replace unmodified posterior results without updating
their interpretation. The earlier methodology notes are in
[the 1.13 preview report](../../analysis/POSTERIOR_MARGIN_SENSITIVITY_2026-10-02.md).

## Measured results

| Step | PoF epsilon=0.0 cells | PoF epsilon=0.01 cells | CVaR cells | CVaR min(mean r_used) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0 | 0 | 0 | 0.014524 |
| 2 | 0 | 0 | 191 | -0.008895 |
| 3 | 0 | 0 | 0 | 0.002264 |
| 4 | 0 | 0 | 0 | 0.091094 |

The requested 200-cell ceiling is satisfied at every step. Step 2 increases
from 69 cells in the 1.13 preview to 191 cells in this preview. The std maps
are updated consistently, with a shared relative-margin std range `[0, 0.033]`.

## Validation

Slurm job `13820255` completed with exit code `0:0` in 99 seconds, using the
renderer at commit `a2b1a75c30717edb86d15859cf3462986eb70157`. All eight PNGs are
6400 by 3388 pixels at 400 dpi. Export checks confirm that titles, ticks, labels,
and annotations fit; the step-2 mean and std images were also visually checked.
Output checksums match, and the red color mask exactly matches negative mean
margin cells. Pressure-difference and saturation arrays are exactly equal to
the verified original arrays for both statistics at all four steps.

The output directory contains `manifest.json`, `validation.json`,
`checksums.json`, and `delivery_verification.json`. Existing data and artwork
were preserved; all 110 snapshotted pre-existing changed/untracked files and
the pre-existing staging contents were unchanged.
