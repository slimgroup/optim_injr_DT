# DTControl statistical figure labels

Requested 2026-09-14; refined 2026-09-15. Figures are identified by filename
and stable slide ID, without page numbers.

## Reviewed exports

Latest requested figures:
`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v5_20260915/`.
All original PNGs and earlier reviewed versions are preserved.

| Slide ID / asset | Filename | Plotting source function | Export method |
| --- | --- | --- | --- |
| `p1-select` | `cdf_POF_eps0.01.png` | `plot_single_cdf` | Render saved numerical objects |
| `p1b-selected-cdf` | `grid_cdf_selected_1x3.png` | `plot_selected_cdf` | Edit historical PNG text regions |
| `p1b-grid-cdf` | `grid_cdf_4x3.png` | `plot_grid_cdf` | Edit historical PNG text regions |
| Single histogram | `hist_POF_eps0.01.png` | `plot_single_hist` | Edit historical PNG title and quantile text |
| Selected histogram | `grid_histogram_selected_1x3.png` | `plot_selected_histogram` | Remove blank spacing; retain panel pixels |

The plotting source is
`scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`.
The previously reviewed `p1b-grid-hist` / `grid_histogram_4x3.png` remains
in `labels_reviewed_v3_20260915/`, byte-identical to its original. Its
labels required no correction; its y-axis is `Count`.

## Final presentation choices

- ECDF y-axis: `Violation probability (%)`, following the user's explicit
  preference. The endpoint interpretation remains in the companion caption.
- Target legend: `Target p = 1%`.
- Single ECDF title: `Optimized-endpoint ECDF (PoF eps = 0.01)`.
- Single histogram title: `Injection Rate Distribution (PoF eps = 0.01)`.
- Grid ECDF title: `Optimized-endpoint ECDFs`, followed by
  `B = 10000; Opt. = Optimistic`. The 95% confidence level remains in the legend.
- Single ECDF legend stays above the axes, outside the confidence band:
  `95% Bootstrap CI (B=10000)`, `Empirical CDF`, `Target p = 1%`.
- Inset abbreviation: `Opt.` means optimistic. The single ECDF retains the
  faint source rectangle and thin connectors to the inset's left corners.
  Rate arrows, markers, and annotation anchor positions are unchanged.
- No bottom footnotes are printed on the figures.
- Rate and summary-statistic annotations use **four decimal places**. This
  explicitly supersedes the initial request to preserve five-place labels.
  Grid values `0.047` and `0.056` become `0.0470` and `0.0560`; the single
  histogram quantile label `0.04831` becomes `0.0483`. Other requested raster
  annotations already had four places. Tick labels, PoF/CVaR parameters,
  counts, bootstrap count, confidence level and target percentage retain their
  existing formats. Neither rate values nor line/marker locations change.
- The selected histogram loses 50 blank pixels above the panel headings and
  50 blank pixels from each horizontal panel gap. Every panel is translated
  without resizing. The source also uses a lower supertitle and narrower gaps.
- Both histogram y-axes remain `Count`.

## Interpretive caption

The ECDF summarizes optimized endpoints across state-permeability pairs.
Assuming that each pair remains feasible below its optimized endpoint, the
fraction of strictly lower endpoints estimates the probability of violating
the selected PoF or CVaR constraint.

The unchanged ECDF counts `q_m <= q`; a member at `q_m = q` remains feasible.
Under the stated assumption the strict violation fraction counts `q_m < q`.
The requested `Violation probability (%)` axis is an interpretive label for
the endpoint ECDF, not a claim of exact physical-fracture or constraint-violation
probability at endpoint ties. The confidence intervals do not claim simultaneous
coverage or a certified 1% bound. This explanation accompanies the exports and
is deliberately kept off the figure canvas.

The [official R ECDF documentation](https://stat.ethz.ch/R-manual/R-patched/library/stats/html/ecdf.html)
uses less than or equal to. Dropping equality gives the left limit of the ECDF.
With 128 samples, one equal endpoint accounts for 0.78125 percentage points;
the convention can matter near a 1% target. The user confirmed calculation
should remain unchanged; no additional ChatGPT consultation is needed.

## Export and verification

`reexport_p1_select_labels.jl` loads the saved `CaseResult` from
`data/figure_exports/figures6_7_decimal4_20260910_005149/case_result.jld2` with
`BOOTSTRAP_DEFINE_ONLY=1`. It calls only `plot_single_cdf`, retaining the
canonical tick formatting. It never collects samples or invokes bootstrap,
quantile/crossing selection, optimization, inference, or forward simulation.
The cache hash is checked before and after rendering. Output directories must
be new.

The single ECDF is checked against the previous plotting source and the source
isolated for commit: curve x/y arrays, confidence-band vertices and path codes,
target line, marker coordinates/styles, annotation anchors/offsets, axis limits,
and tick-label strings are identical. The final PNG is also compared with the
isolated source's rendering.

Complete numerical caches for the historical grid figures were not found.
`relabel_step1_ecdf_exports.py` changes only guarded text regions of the original
ECDF grid PNGs. It pads the two short rates within their original annotation
boxes, retaining the borders and arrows. Slightly smaller numeric type fits
the added zero without expanding a box across the curve. Every pixel outside
the listed text regions is checked against the original; no curve is recovered
or recalculated from the raster.

`refine_step1_statistical_exports.py` assembles the five reviewed figures.
For the single histogram it changes only the title and quantile text; all bins,
bars and selection lines remain pixel-identical. For the selected histogram it
asserts that removed regions are blank, then verifies every retained panel pixel
after translation. No sample data or histogram statistics are recalculated.

Original DPI is retained: 200 for single figures and the full ECDF grid, 220
for selected grids. The selected histogram changes from 3404×1151 to 3304×1101
pixels; panel dimensions are unchanged. The ECDF grids remain 3428×1174 and
2937×2638 pixels. PNG-only originals are not presented as vector exports.
Visual review checks titles, axes, legends, annotation boxes and inset cues.

The output directory includes `caption.md`, `changed_strings.csv`,
`cache_provenance.toml`, `single_numerical_verification.json`,
`png_verification.json`, `input_checksums.json`, and `manifest.json`.
Existing differences between single-case and grid rates are retained.
Original plots, historical rates, injection arrays, data artifacts, and the
separate four-step pressure figure are preserved.

## Commit scope

Earlier presentation revisions were committed as `6238d0f` and `e984723`.
This refinement includes only display formatting/layout, cache-only export
helpers, the five new PNGs and their documentation/verification records.
Pre-existing working-tree changes to ECDF calculations, statistical entry
points, selected-case names, other figures, and monitoring-step workflows stay
outside this commit. No new statistical computation was run.
