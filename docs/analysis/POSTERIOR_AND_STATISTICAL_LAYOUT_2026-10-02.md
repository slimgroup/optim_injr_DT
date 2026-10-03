# Compact posterior titles and separate statistical panels

The requested presentation now uses larger posterior titles with less space
below them, and separate wide 1x3 histogram and ECDF figures for monitoring
steps 2–4. The two supplied step-1 PNGs are visual references only: their rates,
bootstrap count and probability-axis interpretation are not substituted for
the historical step-2–4 results.

## Deliverables

The delivery directory is
`plots/paper_figures/posterior_appendix_e_layout_20261002/`; its ZIP has the same
stem. All exported images are 400-dpi PNGs. No PDF or SVG is generated.

- Eight posterior maps: mean and standard deviation at steps 1–4. The main
  title increases from 20 to 28 points, with six points between the title and
  the case headings. Posterior mean/std arrays, colormaps, color limits, row
  order and spatial orientation remain unchanged.
- Three `injection_rate_histogram_step{k}.png` figures, each with one row of
  the three risk cases. The reference-style legends show sample count, the
  existing sample 1% quantile and the existing historical q-star. The q-star
  line is copied from the corresponding ECDF marker; no new rate is selected.
  Mean and median annotations retain their previous values. The removed
  histogram quantile confidence shading remains absent.
- Three `injection_rate_ecdf_step{k}.png` figures, with the same three cases,
  an internal zoom inset and orange/green/blue crossing annotations. Main ECDF
  and inset line arrays, confidence paths, limits and marker coordinates are
  preserved exactly. Insets and the first-panel legend avoid the main
  confidence bands. The axis remains `Cumulative probability (%)`.

There are 14 distinct figures: 8 posterior + 3 histogram + 3 ECDF. Appendix E
uses 12 (all step-2–4 figures); the two step-1 posterior maps serve the original
main-text request. Canonical-name PNGs and the `paper_compat/` copies represent
the same figures, with matching SHA-256 checksums.

## Source and validation

The renderer is `scripts/python_plots/restyle_paper_pngs.py`. It reads the
checksum-verified NPZ plot snapshots and scientific details from
`posterior_appendix_e_handoff_ecdf_only_20260909`. The original posterior
colormap definitions are loaded from commit
`279108409a3d165ceeed430502c583f9c05e3d3b`. No source PNG is erased, rescaled or
used as the numerical input to the new figures.

Posterior figures are checked against every array in the original plot snapshot,
including colorbar geometry. For split statistical figures, the original axes
are explicitly mapped to the new axes before exact comparison. Histogram
q-star lines are the only added data artists, and their coordinates must equal
the historical ECDF markers. The audit also verifies the retained invisible
histogram interval coordinates; those intervals are not drawn.

Layout checks run at the final 400 dpi and cover canvas clipping, tick overlap,
axis-label clearance, annotation-box overlap and containment inside the inset,
and main-CDF confidence-band visibility. `manifest.json` records the source-to-
paper mapping, generating commit, Slurm job, source script snapshot and output
checksums. Numerical audits are under `validation/`.

The historical ECDF settings remain B=5000 and seed=42. Strict-PoF sample counts
remain 127, 124 and 122 at steps 2, 3 and 4, with 1, 4 and 6 excluded realizations.
Other rate cases contain 128 completed samples each. This layout update does
not resolve any manuscript statement using B=10000 for these historical figures.

Reproduce on a compute node, with a fresh output directory:

```bash
sbatch scripts/shell/submit/submit_paper_png_restyle.sh \
  --output plots/paper_figures/NEW_DIRECTORY
```

## Paper intake

1. Verify the ZIP checksum and the package's `delivery_checksums.json`.
2. Back up the affected manuscript images. Copy `paper_compat/posterior/` PNGs
   to `figs/posterior/`, keeping the existing posterior filenames and QMD IDs.
3. Copy the six `paper_compat/statistical/` PNGs to `figs/statistical/`:
   `grid_histogram_selected_1x3_t{k}.png` and
   `grid_cdf_selected_1x3_t{k}.png`, for k=2,3,4.
4. Each previous `summary_grid_hist_cdf_t{k}.png` now maps to the corresponding
   pair. Update the QMD image references to both new files. Preserve the current
   figure ID and references by using a figure group if appropriate; do not
   overwrite an old combined image with just one of its two new components.
5. Adjust caption references to the separate histogram/ECDF panels while keeping
   the sample qualifications and historical method descriptions. Keep Appendix
   E for these extended results and Appendix D for pressure-bound/BHP material.
6. Render the manuscript to verify placement at its final width. Do not copy
   old 2x3 statistics or preview images over the new 1x3 files.

All older delivery folders, ZIPs, canonical assets, source data and unrelated
working-tree changes are preserved. The new layout uses a separate handoff.
