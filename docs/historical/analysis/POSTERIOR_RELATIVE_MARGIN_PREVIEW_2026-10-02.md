# Posterior relative-margin preview

The user subsequently accepted the focused mean/std option. See
[the accepted handoff and paper intake instructions](../../analysis/POSTERIOR_RELATIVE_MARGIN_ACCEPTED_2026-10-02.md).
The following records the original preview comparison.

This is a review export, not a replacement for the accepted paper PNGs in
`plots/paper_figures/posterior_appendix_e_layout_20261002/`. Statistical rate
figures are outside this change.

The requested new row order is relative margin, pressure difference, and CO2
saturation. Mean and population standard deviation are calculated over the
128 posterior samples at each grid cell, separately for each of the three risk
cases and each monitoring step.

## Definition and interpretation

The relative margin uses the pressure samples from the matching step:

```text
p_max = pres_Hyd + 4e6 Pa
r = (p_max - posterior_pressure) / p_max
```

Both `r` and its standard deviation are dimensionless. The historical float32
loader and population-standard-deviation convention (`ddof=0`) are retained.
The pressure-difference and saturation arrays are independently recomputed
from the original inputs and checked for exact equality with the verified
historical paper caches; the plotted versions reuse those identical caches.

Relative margin is a normalized view of the same pressure field, not an
independent observation. At a fixed cell,
`r = (4 MPa - pressure_difference) / p_max` and
`SD(r) = SD(pressure_difference in Pa) / p_max`.
It adds context about proximity to the pressure limit, rather than new data.

## Two display options

- `wide/`: the earlier relative-margin mean range `[-0.1, 1]`. For standard
  deviation the comparator uses `[0, 1]`, since negative standard deviation
  is not meaningful.
- `focused/`: relative-margin limits derived from the complete range of the
  plotted mean or standard-deviation fields across all four steps and all
  three cases, rounded outward. There is no percentile clipping. Cases and
  steps share the same scale for a given statistic.

Only relative-margin color limits differ between these two options.
Pressure samples are not multiplied or changed for any case. The other two
rows retain their existing colormaps and shared color limits. Both options
retain the compact, enlarged title and aligned colorbars of the accepted
layout. Outputs are 400 dpi PNG only, with distinct filenames describing the
new row order. No paper compatibility filenames are published at this stage.

## Reproduction and validation

```bash
sbatch scripts/shell/submit/submit_posterior_margin_preview.sh \
  --output plots/paper_figures/posterior_relative_margin_preview_20261002_v2
```

Use a fresh output directory for each run; the script refuses to replace an
existing preview. All four source files are required even for a subset of
output steps, so that limits remain comparable across steps.

The preview contains `source_validation.json`, derived-field NPZ files,
`manifest.json`, code snapshots, and `checksums.json`. The source audit checks
the original JLD2 SHA-256 hashes against the historical handoff, verifies the
128-sample shapes, checks the relative-margin identities independently in
float64, and confirms that input files did not change during reading. The
figure audit verifies displayed arrays, absence of color clipping in the new
relative-margin row, unchanged color clipping in retained rows, and text/tick
layout at final export resolution.

The shared focused limits are `[0.02, 0.98]` for the mean and `[0, 0.029]` for
standard deviation. The mean colormap uses warm colors for smaller positive
margins; warm colors by themselves do not indicate a threshold violation.

The existing step-4 mean saturation caches contain 7 cells in PoF epsilon=0.01
and 6 cells in CVaR that are approximately 0.000001 above the old color limit
of 0.9 due to the established float32 reduction. These tiny historical
overshoots, the plotted values, and the 0.9 limit are preserved and recorded.

The completed preview is in
`plots/paper_figures/posterior_relative_margin_preview_20261002_v2/`.
Slurm job `13819342` completed with exit code 0 in 2 minutes 36 seconds.
All 16 PNGs (8 per display option) are 6400 by 3388 pixels at 400 dpi, and all
recorded checksums passed verification. Mean and standard-deviation previews
at steps 1, 2, and 4 were inspected visually. Existing paper assets, source
datasets, and unrelated staged/working-tree changes remain untouched.
