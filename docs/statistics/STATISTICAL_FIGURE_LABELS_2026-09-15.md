# DTControl statistical figure labels

Requested 2026-09-14; refined 2026-09-15. Figures are identified by filename
and stable slide ID, without page numbers.

## Reviewed exports

Latest requested figures:
`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v6_20260915/`.
All original PNGs and earlier reviewed versions are preserved.

| Slide ID / asset | Filename | Plotting source function | Export method |
| --- | --- | --- | --- |
| `p1-select` | `cdf_POF_eps0.01.png` | `plot_single_cdf` | Render saved numerical objects |
| `p1b-selected-cdf` | `grid_cdf_selected_1x3.png` | `plot_selected_cdf` | Edit historical PNG text regions |
| `p1b-grid-cdf` | `grid_cdf_4x3.png` | `plot_grid_cdf` | Edit historical PNG text regions |
| Single histogram | `hist_POF_eps0.01.png` | `plot_single_hist` | Edit title; translate intact panel |
| Selected histogram | `grid_histogram_selected_1x3.png` | `plot_selected_histogram` | Edit title and parameter text |
| `p1b-grid-hist` | `grid_histogram_4x3.png` | `plot_grid_histogram` | Edit title and one statistic label; reduce header spacing |

The plotting source is
`scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`.
Stable filenames retain `eps`; only displayed parameters change to Greek.

## Final presentation choices

- ECDF y-axis: `Violation probability (%)`, following the user's explicit
  preference. The endpoint interpretation remains in the companion caption.
- Target legend: `Target p = 1%`.
- Single ECDF title: `Optimized-endpoint ECDF (PoF ε = 0.01)`.
- Single histogram title: `Injection Rate Distribution (PoF ε = 0.01)`.
  Both single titles increase from 16 to 20 points.
- Both ECDF grids use the single-line title `Optimized-endpoint ECDFs`.
  The selected and full grid titles increase to 24 and 26 points respectively.
  The second line containing `B` and the optimistic definition is removed.
- Both histogram grids use `Distribution of Optimized Injection Rates` at
  24/26 points. `: Histogram` and `(M=128)` are omitted from the title;
  each panel legend retains its sample count. Histogram y-axes stay `Count`.
- Displayed `eps`, `alpha`, and `gamma` become `ε`, `α`, and `γ`. Existing
  Greek parameter titles and their numeric precision are preserved. Case
  lookup keys, filenames, and underlying parameters do not change.
- Grid CI legend: `95% CI, B=10000`. These are the same 95% bootstrap confidence
  intervals as before. **B remains 10000**, the historical resample count;
  the user's `B=1000` wording does not change the recorded calculation.
- The user explicitly accepted keeping both ECDF grid legends in their
  original upper-left locations after being informed that the old translucent
  legend overlaps an uncached curve. Moving it would require reconstructing
  the obscured curve. Only legend text changes; the hidden curve is not guessed.
- Single ECDF legend stays above the axes, outside its confidence band:
  `95% Bootstrap CI (B=10000)`, `Empirical CDF`, `Target p = 1%`.
- `Opt.` means optimistic. Its definition is omitted from the image at the
  user's request; the user will explain it in the presentation.
- All grid inset rate labels (`q_k*`, `ECDF`, `Opt.`) and their numeric values
  use the same nine-point base size and bold weight. Mathematical subscripts
  and superscripts retain their normal relative sizes. The two formerly short
  green/blue boxes in the PoF ε=0.01 panel are slightly widened so four-place
  numbers fit without shrinking type. Original arrow anchors and stars stay
  fixed. Frame/text edits follow the original annotation drawing order.
- Rate and summary-statistic annotations use **four decimal places**. The full
  histogram's `std=0.187` is padded to `std=0.1870`. This supersedes the initial
  request to preserve five-place labels. Tick labels, risk parameters, counts,
  bootstrap count, confidence level, and target percentage keep their formats.
- No bottom footnotes are printed on the figures. The single ECDF keeps its
  faint source rectangle and two thin connectors to the inset's left corners.
- Removed header bands are 75 pixels in the selected ECDF, 55 in the full ECDF,
  and 70 in the full histogram. Panel pixels are translated without resizing.
  The single histogram adds 20 pixels above its panel for the larger title.

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
`BOOTSTRAP_DEFINE_ONLY=1`. It calls only `plot_single_cdf`, retaining canonical
axis ticks. It never collects samples or invokes bootstrap, quantile/crossing
selection, optimization, inference, or forward simulation. The cache hash is
checked before and after rendering. Output directories must be new.

The single ECDF is checked against the previous plotting source and the source
isolated for commit: curve x/y arrays, confidence-band vertices and path codes,
target line, marker coordinates/styles, annotation anchors/offsets, axis limits,
and tick-label strings are identical. The final PNG is also compared with the
isolated source's rendering. No inference or statistical calculation runs.

`polish_step1_statistical_exports.py` uses the guarded v5 assets and the original
full histogram. It records every changed text/frame rectangle. Outside those
regions every raster pixel is verified unchanged before header translation.
The panel translation preserves all retained pixels. Inset annotation boxes
are repainted at a common size; the two widened boxes can cover a slightly
larger background region, as labels do in a native plot. Curves are not
recovered from the PNG or redrawn. Numeric strings are the original historical
values, with trailing zeros only; their placement does not redefine a crossing.
The single-case cache's different rate values are never substituted into grids.

The single histogram's full panel, the histogram bins/bars/selection lines,
ECDF marker and arrow regions, and axis tick formats are preserved. Visual
review checks title/parameter spacing, consistent annotation type, absence of
clipped glyphs, and the original inset cues. Original DPI stays 200 for single
figures/full grids and 220 for selected grids. PNG-only originals are not
presented as vector exports.

The output directory includes `caption.md`, `changed_strings.csv`,
`cache_provenance.toml`, `single_numerical_verification.json`,
`png_verification.json`, `input_checksums.json`, `visual_review.json`, and
`manifest.json`. Earlier export tools remain available for reproducing their
respective historical layouts.

Original plots, historical rates, injection arrays, data artifacts, and the
separate four-step pressure figure are preserved. Pre-existing working-tree
changes to ECDF calculations, statistical entry points, selected-case names,
other figures, and monitoring-step workflows stay outside this commit.

## Commit scope

Earlier presentation revisions were committed as `6238d0f`, `e984723`, and
`dee3c8e`. This refinement includes display typography/layout, Greek labels,
the six new PNGs, the guarded polishing tool, and verification/documentation.
No bootstrap, inference, optimization, crossing selection, threshold testing,
or forward simulation was run.
