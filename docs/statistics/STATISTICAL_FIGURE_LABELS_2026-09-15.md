# DTControl statistical figure labels

Requested 2026-09-14; refined through 2026-09-16. Figures are identified by filename
and stable slide ID, without page numbers.

## Reviewed exports

Latest ECDF grids (`p1b-selected-cdf`, `p1b-grid-cdf`):
`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v7_20260916/`.
The single ECDF and all three histograms remain at v6:
`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v6_20260915/`.
All original PNGs and earlier reviewed versions are preserved.

| Slide ID / asset | Filename | Plotting source function | Export method |
| --- | --- | --- | --- |
| `p1-select` | `cdf_POF_eps0.01.png` | `plot_single_cdf` | Render saved numerical objects |
| `p1b-selected-cdf` | `grid_cdf_selected_1x3.png` | `plot_selected_cdf` | Accepted raster recovery and legend relocation from v6 |
| `p1b-grid-cdf` | `grid_cdf_4x3.png` | `plot_grid_cdf` | Accepted raster recovery and legend relocation from v6 |
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
- Grid CI legend: `95% Bootstrap CI (B=10000)`. These are the historical 95% bootstrap confidence
  intervals as before. **B remains 10000**, the historical resample count;
  the user's `B=1000` wording does not change the recorded calculation.
- Each ECDF grid has one legend in the first panel's upper-right corner.
  The user approved the v7 previews after being informed that removing the
  old translucent legend requires image-level recovery, not lossless recovery
  from numerical plotting objects. The earlier v6 legends stay upper left
  in the preserved v6 files. See the v7 method and limitation below.
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

### v7: approved upper-right grid legends

The user approved the displayed previews on 2026-09-16: move the legends to
the upper right and adopt v7. Each grid retains just one legend, in its first
subplot. Its three entries are `95% Bootstrap CI (B=10000)`, `Empirical CDF`,
and `Target p = 1%`. The single-line title remains `Optimized-endpoint ECDFs`;
there is no on-image optimistic definition.

`relocate_step1_ecdf_legends.py` reads the hash-guarded v6 PNGs and original
full-grid PNG. The historical paper export at
`ad0696e:plots/paper_figures/statistical/grid_cdf_selected_1x3.png` explicitly
labels PoF epsilon=0 as identical to CVaR gamma=0. The script therefore reuses
the unoccluded second-row, first-column panel to fill the old legend region.
The full grid uses integer pixel translation. The selected grid registers
the donor using visible axis tick positions and bicubic affine resampling.
This is an accepted raster restoration of the obscured region, **not verified
lossless recovery of its original curve or confidence-band pixels**. No new
statistical values are calculated, and no numerical cache or sample is read.

The source plotting functions also place their first-panel legends at
`upper right` with the same text. Those source functions were not executed:
there is no complete frozen numerical cache for either grid.

Verification checks unchanged dimensions/DPI and pixel identity everywhere
outside the old/new legend rectangles. Titles, axes, insets, markers, arrows,
four-decimal rate annotations, and every other panel are unchanged from v6.
Final exports are also compared against the exact temporary previews approved
by the user. All original and v6 files remain untouched.

Reproduce into a **new** directory using:

```bash
python scripts/python_plots/relocate_step1_ecdf_legends.py \
  plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v6_20260915 \
  NEW_OUTPUT_DIR --accept-raster-recovery
```

The v7 directory includes the two PNGs, the interpretive `caption.md`, and
`legend_relocation_verification.json` recording sources, hashes, registration,
changed rectangles, and the raster-recovery limitation. The other four assets
need no further export and remain at v6.

### v6: typography, four decimals, and compact headers

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
`dee3c8e`; v6 was committed as `072cdd2`. The v7 refinement includes only two
grid legend display changes, their accepted PNG exports, the guarded raster
relocation script, and verification/documentation. Unrelated existing numerical
and working-tree changes remain outside the commit.
No bootstrap, inference, optimization, crossing selection, threshold testing,
or forward simulation was run.
