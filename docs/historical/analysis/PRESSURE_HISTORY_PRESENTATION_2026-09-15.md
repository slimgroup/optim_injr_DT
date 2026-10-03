# Pressure-history presentation audit — 2026-09-15

On **2026-10-02**, both this figure and
[`injection_schedule_over_four_steps.png`](../../../plots/paper_figures/injection_schedule_over_four_steps.png)
were polished to the same 3840 × 2160 layout, with identical axes positions,
font sizes, case labels, legend anchors and event-marker styling. Both marker
legends now read **Severe pressure exceedance (day 728)**. The pressure figure's
filled stars were initially reduced from `s=531.25` to `s=110` points squared.
Following further readability feedback, both figures now use `s=300`: approximately
22% larger in width and height than the preceding `s=200` version, with the same
0.8-point white edges. The user accepted slight contact between the pressure
stars' tips; both stars remain visually distinct. Their data coordinates and
both axis ranges are unchanged.
The annotations remain **Pressure ratio: 1.1073** and **Peak: 6,953 cells**.

All eight curves in each figure, reference-line coordinates and event-marker
centers were compared exactly against the pre-edit renderers. Pressure limits
remain `[0.77, 1.146055237910414]` and `[0, 8000]`; injection limits remain
`[0, 0.225]` and `[0, 11.563237969920001]`. Both time axes remain `[0, 1920]`.
JLD2 input hashes are unchanged, and the temporary regenerated injection CSV
is byte-identical to the existing CSV, which was left untouched. The schedule
figure still uses base schedules; the pressure figure still uses its documented
sensitivity sources. No data-source substitution was made to match layouts.
Both PNGs were visually reviewed and checked for clipped text and overlapping
legends/titles. This revision supersedes the marker-size and naming notes below.

On **2026-09-27**, the day-728 endpoint markers were updated using the retained
v2 dual-axis figure as the baseline. The new
[PNG](../../../plots/paper_figures/pressure_risk_trajectory_over_four_steps.png) and
[audit JSON](../../../plots/paper_figures/pressure_risk_trajectory_over_four_steps.json)
use the requested original filename; the v2 PNG and its audit remain unchanged.
Both endpoints now use red five-point stars, with linear dimensions 25% larger
(`scatter s: 340 → 531.25`). Following the user's refinement, both are filled
red with identical white edges: the left-axis pressure ratio
`1.107299746773347` (displayed as `1.1073`) and the right-axis count `6,953`.
Callouts read **Pressure ratio: 1.1073** and **Peak: 6,953 cells**, without
axis-name suffixes as requested. There is one shared marker legend entry:
**No-control shutdown (day 728)**. The left-axis label and solid-line legend
now read **Maximum pressure-to-limit ratio**. The markers remain close because
their actual data coordinates and both axis ranges are preserved.

The current limits are unchanged: time `[0, 1920]`, ratio
`[0.77, 1.146055237910414]`, count `[0, 8000]`. The ratio floor is a fixed
plotting choice; its ceiling is `max(1.13, shutdown_ratio × 1.035)`.
The count floor is zero; its ceiling is
`max(2000, ceil(max_plotted_count × 1.10 / 2000) × 2000)`:
`6953 × 1.10 = 7648.3`, rounded upward to `8000`.
These are independent display ranges with headroom, not a calibration or
conversion between the two quantities. The older original generator used
count limits `[-180, 7648.3]`; those are historical, not the retained v2 limits.
All eight plotted curves, reference lines, ticks and axes positions were
compared against the pre-edit renderer and are exactly unchanged. Star and
callout anchors use their respective axis's data coordinates; only callout
text is offset. Input JLD2 hashes and the v2 PNG hash are unchanged. Exported
text and legends were checked for clipping and overlap with the title.

The notes below describe earlier revisions.

On **2026-09-16**, the user requested PNG-only output and removal of older
images. The latest v2 PNG is the only retained image export for this figure;
the original PNG, the earlier stacked and dual-axis PNGs, and all three versions'
PDF/SVG exports were removed. This supersedes the historical preservation notes
below. JLD2 inputs, scripts, and JSON audit records remain intact. The rendering
script now exports only PNG plus its JSON audit sidecar and no longer needs the
deleted original PNG as an input. The latest PNG and its font sizes are unchanged.

## Current revision v2: original layout, larger text, concise annotations

Following user feedback, the current preferred export restores the original
single plot with **two independent y axes**, the separate boxed **Cases** and
**Line meaning** legends, and the original colored peak callout boxes. The
left-axis label is shortened to **Maximum pressure ratio [-]**, defined as
`max(p_res/p_max)`. The right label remains **Pressure-exceeding cells [-]**;
the threshold now reads **Fracture pressure limit (ratio = 1)**, as requested.
A teal boxed note states **PoF ε=0.0: 0 exceeding cells**, with the count derived
from the unchanged saved trajectory. Axis labels increased from 19 to 21 pt,
ticks from 16 to 18 pt, legend entries from 13 to 15 pt, peak callouts from
13.5 to 15 pt, and the title from 22 to 24 pt. The enlarged legends reduce
the gap above the title; removal of the footer also gives the axes more room.

“No-control severe fracture (day 728)” is retained in the legend. The user asked
to remove the small footer, so the footer and its footnote asterisk are removed.
The criterion remains documented here: the first saved output with
`min(r) <= -0.1`, where `r = (p_max-p)/p_max`, equivalently
`max(p/p_max) >= 1.1`. Both the original generator's `SEVERE_MARGIN` and the
JLD2 field `severe_margin_threshold` are `-0.1`. At day 720, `min(r)` is
`-0.07600260843579872`; at day 728 it is `-0.1072997467733469`. The recorded
event is therefore the 91st saved output, day 728, rather than an exact equality
to `-0.1`. This is the scenario's numerical shutdown criterion.
The red star uses ratio-axis coordinates `(728, 1.107299746773347)`; a small open
circle and the original peak callout use count-axis coordinates `(728, 6953)`.
The axes remain independently scaled: ratio `[0.77, 1.146055237910414]` and
count `[0, 8000]`. No curve values or time samples changed.

Current files:

- [PNG, 3840 × 2160](../../../plots/paper_figures/pressure_risk_trajectory_over_four_steps_content_revision_v2_20260915.png)
- [Audit JSON](../../../plots/paper_figures/pressure_risk_trajectory_over_four_steps_content_revision_v2_20260915.json)

The same plotting script now defaults to this dual-axis presentation. Use
`--layout stacked --output-stem <fresh-name>` to reproduce the earlier layout.
Earlier images were removed at the user's request on 2026-09-16. The audit below
documents the original numerical checks and the previous stacked version.

## Earlier stacked version and numerical audit

Target: slide 40, `p1-pressure-result`, with the source identifier
`SLIM.Papers.DTControl/figs/pressure_risk_trajectory_over_four_steps.png`.
This workspace contains the original plot and generator under `optim_injr_DT`;
the separate `SLIM.Papers.DTControl` slide repository was not located or edited.
The new assets are ready for placement on that slide. A byte-for-byte comparison
against the separate slide repository's image was therefore not possible.

Only presentation changed. No simulation or optimization was run. All eight
plotted curves retain their original time and value arrays exactly, including
initial points and the day-728 cutoff. All four cases, colors, schedules, source
selection, and monitoring boundaries are unchanged.

## Historical deliverables

The earlier `pressure_risk_trajectory_over_four_steps_presentation_20260915`
PNG/PDF/SVG exports and the original `pressure_risk_trajectory_over_four_steps.png`
were removed on 2026-09-16. Their provenance is retained in the following files:

- [Machine-readable audit and source SHA-256 hashes](../../../plots/paper_figures/pressure_risk_trajectory_over_four_steps_presentation_20260915.json)
- [New plotting script](../../../scripts/python_plots/plot_pressure_risk_trajectory_presentation.py)
- [Unchanged original plotting script](../../../scripts/python_plots/plot_pressure_risk_trajectory_over_four_steps.py)

The new script refuses to overwrite existing exports. To reproduce under a fresh
name, run `python scripts/python_plots/plot_pressure_risk_trajectory_presentation.py --output-stem plots/paper_figures/pressure_history_REVIEW_NAME`.

## Label changes

| Before | After |
| --- | --- |
| Ground-Truth Pressure Risk Across Four Monitoring Steps | Reservoir pressure exceedance over four monitoring steps |
| Maximum normalized pressure load [-] | Maximum pressure-to-limit ratio [-] |
| Fractured cells [-] | Pressure-exceeding cells [-] |
| Fracture-pressure threshold | Model pressure limit (ratio = 1) |
| No-control severe fracture (legend) | No-control shutdown (day 728), with separate ratio and count markers |
| Separate external “Cases” and “Line meaning” legend boxes | One compact row of the four case identities; metric identity is given by each panel's axis label |

Per the user's preference, “Severe fracture” remains in the figure footer as the
name of the **model shutdown criterion**, with its formula and clarification
that no physical fracture is simulated. It is not presented as a calibrated
physical failure prediction.

## Quantities and normalization

At each existing saved time `h`, the intended and implemented metrics are

```text
L(h) = max over (i,j) of p_res[i,j,h] / p_max[i,j]
N(h) = sum over (i,j) of 1[p_res[i,j,h] > p_max[i,j]]
r(i,j,h) = (p_max[i,j] - p_res[i,j,h]) / p_max[i,j]
```

The original Python helper uses `np.max(pressure / p_max, axis=(1, 2))` and
`np.count_nonzero(pressure > p_max, axis=(1, 2))` (lines 41–45). JLD2 arrays read
through h5py are oriented `(time, z, x)`; the saved `p_max` is `(z, x)`.
`p0` is transposed when needed. These are absolute reservoir pressures, not
pressure differences or a window-normalized pressure increment.

For every selected file containing pressure fields, direct array comparison
confirms `p_max = p0.T + 4e6 Pa`, i.e. hydrostatic pressure plus 4 MPa. The limit
ranges from 4.0625 to 20 MPa. The initial maximum ratio is 0.8 and the initial
count is zero. The PoF sensitivity export lacks pressure fields and stores the
diagnostics only; its generating script uses the same normalization.

`N(h)` is an instantaneous count of reservoir cells. It is not a cell-time PoF,
a cumulative count over time, a count of distinct cells ever exceeding the
limit, or a count of simulated fracture events.

## Exact source selection and verified peaks

All data files below remain in `plots/paper_figures/`, as in the original script.
All selected exports identify ground-truth permeability sample **2000**.

| Case | Existing source and plotted arrays | Sampling retained | Peak count |
| --- | --- | --- | ---: |
| PoF ε=0 | `forward_sim_four_steps_base_data.jld2`: `POF_eps0_pres_snaps`, `p_max`, `POF_eps0_snap_idx` | 80-day snapshots to 1920 days; 25 plotted points including t=0 | 0 |
| PoF ε=0.01 | `pof_eps001_full_campaign_sensitivity_1p65x.jld2`: `max_pressure_load_by_substep`, `fractured_cells_by_substep`, `dt_days` | 8-day diagnostics to 1920 days; 241 plotted points including t=0 | 8 at day 408 |
| CVaR α=0.01, γ=0.1 | `full_campaign_video_CVaR_g01_a001_sensitivity.jld2`: `1 - min_margin_by_substep`, `fractured_cells_by_substep` | 8-day diagnostics to 1920 days; 241 plotted points including t=0 | 2,285 at day 408 |
| No control | `no_control_delayed_ramp_10_periods.jld2`: `pres_all`, `p_max`, `dt_days`, `severe_day` | 8-day snapshots through day 728 only; 92 plotted points including t=0 | 6,953 at day 728 |

All four requested peak counts match the existing source. The PoF ε=0 maximum
is over its original saved 80-day snapshots; this revision does not add or infer
intermediate samples. Its saved `POF_eps0_first_fracture_substep` is also zero.

The original plot deliberately replaces two base-case trajectories with the
existing **PoF schedule ×1.65** and **CVaR schedule ×1.22** sensitivity exports.
Those exact choices remain unchanged; they must not be described as unscaled
base schedules. The no-control source uses a 10-period ramp from 0 to 0.2 m³/s.

Source generators inspected, but not executed:

- `scripts/julia_scripts/data_collection/forward_exports/run_forward_four_steps_base_export.jl`
- `scripts/julia_scripts/data_collection/forward_exports/run_pof_eps001_full_campaign_sensitivity_sweep.jl`
- `scripts/julia_scripts/data_collection/forward_exports/run_full_campaign_video_cases.jl`
- `scripts/julia_scripts/data_collection/forward_exports/run_no_control_delayed_fracture_sweep.jl`

The CVaR ratio is actually loaded as `1 - min_margin_by_substep`, which is
mathematically equivalent to `max(p_res/p_max)` for this relative margin. Its
saved diagnostics were calculated from the original Float64 pressure before
the pressure snapshots were cast to Float32. Recomputing from those rounded
snapshots yields a maximum absolute ratio difference of `3.573642537446631e-8`.
At **day 896**, the saved count is **1,912**, while the Float32 field gives
**1,911** because one cell rounds exactly onto its pressure limit. No other
saved CVaR time changes count under that check. The original Float64-derived
diagnostics, including 1,912, are retained; neither trajectory nor peak was
“corrected” using the lower-precision snapshots.

## Axis and marker findings

| Axis | Original limits | New limits |
| --- | --- | --- |
| Pressure ratio | `[0.77, 1.146055237910414]` | `[0.77, 1.146055237910414]` |
| Cell count | `[-180, 7648.3]`, including a zero tick | `[0, 8000]` |

The original star is created by `ax_load.scatter([severe_day], [severe_load])`
(lines 146–158): it belongs to the **pressure-ratio axis in data coordinates**.
The adjacent “Peak: 6,953 cells” annotation is separately placed with
`ax_cells.annotate`, in count coordinates. There was no count-axis star.

At day 728, the two original vertical positions as fractions of axis height are

```text
ratio: (1.107299746773347 - 0.77) / (1.146055237910414 - 0.77)
       = 0.8969420254523893
count: (6953 - (-180)) / (7648.3 - (-180))
       = 0.9111812270863405
```

They differ by about 1.424% of the plot height, explaining the near meeting.
Both metrics derive from pressure, but their visual near intersection conveys
no physical equality, calibration, or conversion between the quantities.

The replacement uses two vertically stacked panels with one shared time axis.
It preserves the original pressure-ratio range and gives counts an independent
linear scale starting at zero. Neither data nor scales were chosen to align
the markers. Both panels contain a red vertical line at day 728 and their own
data-coordinate star: `(728, 1.107299746773347)` above, `(728, 6953)` below.
The four monitoring intervals are 0–480, 480–960, 960–1440 and 1440–1920 days.

## Shutdown rule and values

The no-control source records `severe_margin_threshold = -0.1`,
`severe_substep = 91`, `dt_days = 8`, and `severe_day = 728`.
This is the **first saved output** satisfying

```text
min(r) <= -0.1  <=>  max(p_res/p_max) >= 1.1
```

At day 728: `min(r) = -0.1072997467733469`,
`max(p_res/p_max) = 1.107299746773347`, and `N = 6953`.
At the preceding saved output, day 720, `min(r) = -0.07600260843579872`, so
the threshold had not yet been crossed. No continuous-time crossing between
saved outputs is inferred.

The historical export completes its 80-day solver block before breaking, so
the file contains 100 outputs through day 800. The original figure explicitly
clips this file at `severe_day`. The new figure retains exactly that cutoff;
it does not plot days 736–800 or append any later no-control history. Calling
day 728 the shutdown refers to the documented scenario event, not a claim that
the export routine physically halted the solver at that precise substep.

## Validation and preservation

- Captured the original script's plotted lines with `Figure.savefig` disabled;
  compared the new x/y arrays against every original line with
  `numpy.testing.assert_array_equal`: all eight curves match exactly.
- Checked both new stars' actual data coordinates and both day-728 lines.
- Confirmed all four requested peak counts directly from the selected sources.
- Compared SHA-256 hashes before and after rendering for all four JLD2 inputs,
  the original script, and original PNG: unchanged. The hashes are in the JSON.
- Original PNG SHA-256: `25ae8fab3f8138d125b207fd8b45bfbb9973c8a9043ab2515123d119d87f6156`.
- Checked visible text extents against the export canvas and visually inspected
  the rendered 16:9 layout; no clipped labels, titles, or annotations.
- The four original case colors, solid ratio lines and dashed count lines are
  retained. No interpolation, smoothing, resampling, or post-shutdown extension
  was introduced.

This was a lightweight saved-array audit and single-figure render. No Julia
entry points, simulation inputs, optimization code, batch interfaces, existing
analysis exports, or unrelated user changes were modified.
