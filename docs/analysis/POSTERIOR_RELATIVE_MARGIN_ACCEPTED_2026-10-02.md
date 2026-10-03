# Accepted focused posterior mean and standard deviation

The user accepted the focused relative-margin preview and requested that the
standard-deviation figures be updated as well. The new PNG-only handoff is
`plots/paper_figures/posterior_relative_margin_focused_20261002/`.
It contains the accepted 8 posterior mean/std maps for steps 1–4 and the 6
unchanged separate histogram/ECDF panels for steps 2–4. All images are 400 dpi.
No old export, dataset, or paper-repository file is overwritten.

## What focused changes

Pressure values are multiplied by **1**, including PoF epsilon=0.01 and CVaR.
Only the relative-margin row's linear color normalization is changed:

| Statistic | Wide-preview color limits | Accepted focused limits | Normalized scale slope ratio |
| --- | --- | --- | --- |
| Mean relative margin | -0.1 to 1.0 | 0.02 to 0.98 | 1.1 / 0.96 = 1.145833 |
| Standard deviation of relative margin | 0 to 1.0 | 0 to 0.029 | 1 / 0.029 = 34.482759 |

These ratios describe the slope of the numerical mapping into the colormap,
not multiplication of pressure, margin, uncertainty, or perceived color
contrast. The mean mapping also shifts its lower endpoint. The colormap itself
is unchanged between the wide and focused previews. Warm colors in the mean
map indicate smaller positive margins; they do not in themselves mean that
the fracture threshold was exceeded. All three cases and all four steps share
the same limits, with no clipping in the new relative-margin row.

The three rows are relative margin, pressure difference, and CO2 saturation.
For standard deviation, all three rows are the corresponding pointwise
population standard deviations across the 128 posterior samples (`ddof=0`).
The pressure-difference and saturation row arrays, color limits, colormaps,
orientation, and units remain those of the previous accepted delivery.

The definition remains `r = (p_max - p) / p_max`, with `p_max = pres_Hyd + 4 MPa`
from each matching step file. At a fixed grid cell,
`SD(r) = SD(p - pres_Hyd in Pa) / p_max`. The first two standard-deviation rows
therefore remain related views of the same pressure uncertainty.

## Files and reproducibility

Posterior names explicitly identify the new row order:

```text
posterior/posterior_mean_relative_margin_pressurediff_sat_step{k}.png
posterior/posterior_std_relative_margin_pressurediff_sat_step{k}.png
```

New manuscript-name copies live under `paper_compat/posterior/`, named
`state_mean_relative_margin_pressurediff_sat_all_cases_t{k}.png` and
`state_std_relative_margin_pressurediff_sat_all_cases_t{k}.png`. These names
avoid overwriting or misidentifying the old pressure-difference / pressure /
saturation layout. `manifest.json` maps old and new paper paths explicitly.

The handoff copies the already rendered, approved focused PNGs byte for byte.
It does not rerender, recompute samples or statistics, or change bootstrap
settings. All 6 statistical PNGs are byte-identical to the previous delivery;
their historical ECDF settings remain B=5000 and seed=42. The purple histogram
quantile interval remains absent.

The lightweight assembly command is:

```bash
python scripts/python_tools/maintenance/assemble_focused_posterior_handoff.py \
  --output plots/paper_figures/posterior_relative_margin_focused_20261002
```

Choose a fresh output directory for subsequent runs. Source manifest hashes,
PNG dimensions/dpi, and paper-copy identity are verified while assembling.
The source audits, derived posterior arrays, prior numerical reports, renderer
snapshots, generating commit, and Slurm job are included in the handoff.
Actual regeneration from original JLD2 inputs continues to use
`submit_posterior_margin_preview.sh` on Slurm, with `--variants focused`.

## Paper-repository intake prompt

<!-- PAPER_PROMPT_START -->
Use the PNGs in posterior_relative_margin_focused_20261002/ to update the paper.

1. Verify manifest.json and delivery_checksums.json. This delivery uses the
   accepted focused posterior mean/std figures: eight images for k=1–4, all
   400 dpi PNGs.
2. Row order is relative margin, pressure difference, and CO2 saturation.
   Copy the new files from paper_compat/posterior/ into figs/posterior/:
   state_mean_relative_margin_pressurediff_sat_all_cases_t{k}.png
   state_std_relative_margin_pressurediff_sat_all_cases_t{k}.png
   Update QMD paths using the manifest's paper_current_path → paper_new_path
   mapping. Preserve Quarto IDs, cross references, and old figures; do not
   overwrite old row-order filenames with this new layout.
3. Update mean/std captions to describe the three rows. Statistics are computed
   across 128 posterior samples at each reservoir grid cell, using population
   standard deviation (ddof=0). Relative margin is r=(p_max-p)/p_max, with
   p_max=pres_Hyd+4 MPa. Margin and saturation are dimensionless; pressure
   difference is in MPa.
4. Keep the case order: PoF epsilon=0.0, PoF epsilon=0.01, and
   CVaR gamma=0.1 / alpha=0.01. Titles use monitoring index k.
   The focused variant changes only relative-margin color limits: mean
   0.02–0.98 and standard deviation 0–0.029, shared across cases and steps.
   Pressure data are not amplified or modified in this variant. Warm colors
   indicate smaller margins, not necessarily pressure exceedance.
5. The six previously accepted statistical figures are included byte for byte.
   If the paper already uses the separate 1×3 histogram/ECDF figures, leave
   them as they are. Otherwise copy from paper_compat/statistical/:
   grid_histogram_selected_1x3_t{k}.png
   grid_cdf_selected_1x3_t{k}.png
   for k=2–4, replacing each combined-figure reference with the two panels
   while preserving figure IDs and cross references.
6. Historical ECDF settings remain B=5000 and seed=42, not 10000; the q-star
   selection algorithm is unchanged. The purple histogram quantile confidence
   interval remains absent. Preserve the strict-PoF sample qualifications:
   127/124/122 feasible completed rate samples at k=2/3/4, with 1/4/6 excluded.
   Other rate cases use 128. Do not apply rate-subset counts to posterior maps.
7. Appendix E uses six posterior and six statistical figures for k=2–4; the
   two k=1 posterior figures go in the main text. Preserve Appendix D's
   pressure-bound/BHP content. Render and check captions, widths, IDs, and
   cross references.
<!-- PAPER_PROMPT_END -->
