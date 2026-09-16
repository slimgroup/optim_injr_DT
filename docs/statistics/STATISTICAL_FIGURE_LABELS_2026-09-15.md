# DTControl statistical figure labels

Requested 2026-09-14; implemented 2026-09-15. Assets are identified by stable
slide IDs and filenames, without page numbers.

## Sources and exports

The current plotting source is
`scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl`.
Original exports remain in
`plots/DT_control/exp_name=step1/statistical_analysis/ecdf/`.
The latest single-case export is in `labels_reviewed_v4_20260915/`.
The selected grid, full grid, and histogram remain in `labels_reviewed_v3_20260915/`.
All earlier exports are preserved.

| Slide ID | Filename | Source function | Export status |
| --- | --- | --- | --- |
| `p1-select` | `cdf_POF_eps0.01.png` | `plot_single_cdf` | Reviewed; rendered from the saved numerical cache |
| `p1b-selected-cdf` | `grid_cdf_selected_1x3.png` | `plot_selected_cdf` | Reviewed; text-only update of the original PNG |
| `p1b-grid-cdf` | `grid_cdf_4x3.png` | `plot_grid_cdf` | Reviewed; text-only update of the original PNG |
| `p1b-grid-hist` | `grid_histogram_4x3.png` | `plot_grid_histogram` | Reviewed; byte-identical copy, no label correction needed |

The lowercase paper-facing single-case file is a different historical asset.
This task targets the requested uppercase `cdf_POF_eps0.01.png`. Existing paper
copies and the separate decimal4 exports are preserved.

## Changed strings

- ECDF y-axis: `Fracture Probability (%)`, `Fracture Prob. (%)`, and the single
  inset's `Frac. Prob. (%)` become `Violation probability (%)`, following the
  user’s explicit preference after the initial endpoint-CDF labeling review.
  The 4×3 label uses 12-point type to fit each row without changing the canvas.
- Target legend: `1% Fracture Probability` / `1% Fracture Prob.` become
  `Target p = 1%`.
- Selected and full-grid title:
  `Fracture Probability vs Injectivity: Empirical CDF with Bootstrap CI`
  with `(B=10000, 95% CI)` becomes
  `Optimized-endpoint ECDFs` followed by
  `B = 10000; Opt. = Optimistic`. The unchanged inset abbreviation is explicitly
  defined so it cannot be confused with optimal. The 95% level remains in the legend.
- Following the user’s visual feedback, the single-case title is now
  `Optimized-endpoint ECDF — PoF eps = 0.01`. The legend moves above the axes,
  outside the confidence band. The current legend reads
  `95% Bootstrap CI (B=10000)`; the inset abbreviation is `Opt.` (optimistic).
  These latest choices follow the user’s request to simplify the single figure.
- The single-case inset uses the selected-grid style: a faint gray source
  rectangle and thin corner connectors, routed to the left corners to avoid the
  inset x labels. The colored rate arrows and their anchors are retained.
- Both bottom text lines were removed at the user’s request. Mathematical
  interpretation remains in the accompanying caption/documentation.
- Histogram titles and rate-selection annotations have no inappropriate
  fracture-probability wording; its y-axis remains `Count`.

All affected ECDF axes use percentages, so `(%)` is retained. No data rescaling,
rate reformatting, quantile alignment, or crossing recalculation is performed.

## Caption

The ECDF summarizes optimized endpoints across state-permeability pairs.
Assuming that each pair remains feasible below its optimized endpoint, the
fraction of strictly lower endpoints estimates the probability of violating
the selected PoF or CVaR constraint.

The unchanged ECDF counts `q_m <= q`; a member at `q_m = q` remains feasible.
Under the stated assumption the strict violation fraction counts `q_m < q`.
The user-selected `Violation probability (%)` label is an interpretive label
for the unchanged endpoint ECDF, not a claim that its values at endpoint ties
are exact physical-fracture or constraint-violation probabilities. Titles and
legends continue to identify the plotted object as an ECDF. The confidence
intervals do not claim simultaneous coverage or a certified 1% bound.

The standard ECDF is `F_n(q) = count(q_m <= q) / M`. Dropping equality gives its
left limit `F_n(q-) = count(q_m < q) / M`. The difference is the mass tied at
`q`; with 128 members, one equality accounts for `100/128 = 0.78125` percentage
points. This is material near a 1% target. This labeling revision therefore
preserves the existing numerical objects, crossing positions and historical
selected rates; it does not change ECDF calculation conventions.

## Validation and reproducibility

`reexport_p1_select_labels.jl` loads the complete saved `CaseResult` from
`data/figure_exports/figures6_7_decimal4_20260910_005149/case_result.jld2` using
`BOOTSTRAP_DEFINE_ONLY=1`. It calls only the single-case plotting function;
it does not collect raw samples, compute statistics, bootstrap, or calculate
crossings. The original canonical PNG's numerical formatting is retained.
The script refuses an existing output directory.

The refined single-case PNG is 1600×1285 at 200 DPI. Its plotting area stays
fixed; the title and legend, including the bootstrap count, sit above the axes.
Removing the footer shortens the canvas. A comparison of the actual Matplotlib objects before
and after the refinement verifies exact equality of curve arrays,
confidence-band vertices and path codes, target line, marker coordinates and
styles, annotation anchors and offsets, and axis limits. No statistics were
recomputed. Visual inspection confirms the new text fits and the legend no
longer covers the confidence band. The light inset connectors avoid the inset x labels. The histogram is byte-identical to its original. The source
version isolated for the commit was independently rendered from the same
cache and has identical numerical plot objects.

The grid PNGs have no complete numerical cache or serialized/vector figure in
the checked locations. After the user requested both grids be updated following
the proposed text-replacement approach, `relabel_step1_ecdf_exports.py` changes
only the title, y-axis labels, and target-legend text regions of the original
PNGs. It verifies the input hashes and refuses existing outputs. Every pixel
outside the documented text regions is identical to the original; all insets
and numerical annotations are pixel-identical. No numerical curve is
reconstructed and no sample data are read. The original grid dimensions and
PNG resolutions are preserved: 3428×1174 at 220 DPI for the selected grid,
2937×2638 at 200 DPI for the full grid. No PDF or vector format is fabricated
from these PNG-only originals.

The short grid inset labels `Opt.` are preserved to avoid changing the small
annotation boxes; `Opt. = Optimistic` is stated in the header. The single-case
inset now also uses `Opt.`; the abbreviation means optimistic, not optimal. Existing differences between the
single-case and grid rate values are preserved. The mathematical distinction
between the ECDF and a strict violation fraction is unchanged and stated in
the caption accompanying the requested `Violation probability (%)` axis label.

`input_checksums.json`, `single_numerical_verification.json`,
`grid_verification.json`, `p1-select_cache_provenance.toml`, `manifest.json`,
`changed_strings.csv`, and `caption.md` accompany the reviewed figures. Historical rates, injection
arrays, simulations, existing exports, and the four-step pressure figure are
preserved. Pre-existing working-tree edits are preserved; this task's source
changes are confined to labels, typography, and single-case legend/title
placement in the three target CDF functions. Calculation functions, histogram
functions, rate-formatting helpers, and statistical entry points are unchanged.


## Commit scope

Commit `6238d0f` contains the labeling task, its two export helpers, reviewed
v3 exports, and provenance/verification records. The v4 refinement changes
only the single-case presentation and its supporting records. The shared Julia
source is staged with the display changes and the definition-only guard needed
by the cache exporter. Pre-existing working-tree changes to statistics,
selected-case names, rate formatting, monitoring steps, and other figures are
preserved outside this commit. No inference, optimization, bootstrap,
threshold testing, or forward simulation was rerun.


## ECDF definition reference

The user confirmed that calculation should stay unchanged. The [official R
stats ECDF documentation](https://stat.ethz.ch/R-manual/R-patched/library/stats/html/ecdf.html)
defines the ECDF using observations less than or equal to the evaluation point.
This was independently checked against the documentation; no separate ChatGPT
conversation or statistical recalculation was used. The v4 figure removes the
on-canvas distinction note for a cleaner layout, as requested, while preserving
the mathematical explanation above.
