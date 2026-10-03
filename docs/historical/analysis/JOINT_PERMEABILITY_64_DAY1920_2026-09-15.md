# Joint permeability movie: 64 members at Day 1920

The user approved the [64-member proposal](../../analysis/joint_perm_64_day1920_proposal_20260915/README.md)
and its maximum 320.5 allocated core-hours on 15 September 2026. Although the user
also allowed choosing a different rate for a 480-day illustration, this run
uses the approved 1920-day plan and existing selected PoF epsilon=0.01 schedule.

Run directory:
`data/forward_comparisons/joint_perm_day1920_64_20260915T062645Z/`.
The original 32-member Day 480 run and its outputs remain intact. 32 members
resume from their own saved Day 480 states; 32 new members begin at the identical
common initial state. The schedule is identical across all 64 realizations.
It is replayed continuously with no posterior updates or new optimization.

The 64 positions were fixed by the proposal before the added outcomes were
available. All 64 geological realization IDs are distinct. Initial pressure,
initial CO2 saturation, porosity, grid, wells and cellwise pressure limit are
checked against the original controlled comparison. The model-library
versions are fixed to Jutul 0.2.11, JutulDarcy 0.2.7 and JutulDarcyRules 0.2.8.

## Restart validation and execution

Pilot position 1, Slurm 13211232, first replayed the last 80 days of its saved
Day 480 trajectory from the saved Day 400 pressure and saturation. The maximum
differences from the original Day 480 result were 1.3490207493305206e-6 Pa for
pressure and 6.857014955841123e-14 for saturation, passing the specified 0.1 Pa
and 1e-7 tolerances. Continuation then starts from the original saved Day 480
fields, whose file and field hashes are verified.

Both pilots reached Day 1920 and passed independent field/provenance checks.
Position 1 finished in 13m51s, peak RSS about 3.0 GiB; position 3 finished in
14m30s, peak RSS about 3.9 GiB. The new-member pilot starts at Day 0 with the
same initial pressure and saturation as every member.

| Job | Scope |
|---|---|
| `13211232` | Position 1 restart validation and continuation, completed |
| `13211233` | Position 3 full-campaign pilot, completed |
| `13211342` | Remaining 31 continuations, all completed |
| `13211343` | Remaining 31 full-campaign members, all completed |
| `13211349` | Both movies and 64 frames, completed in 95 seconds |

The Python reader handles JLD2's zero-length string encoding for new members,
whose restart source is intentionally empty. This is a metadata-reading fix;
the forward code and scientific arrays were unchanged. The final renderer
and its helpers are snapshotted under the run's `code/render_final/` directory.

Both pilot allocations are included in the 64-task budget. Saved-state tasks
are limited to 4 CPUs / 16 GiB / 60 minutes; new tasks to 4 CPUs / 16 GiB / 90 minutes.
At most four forwards run together. Rendering receives 2 CPUs / 8 GiB / 15 minutes.
The total allocation ceiling is 320.5 core-hours; expected usage is lower.

All 65 allocations finished successfully with exit code `0:0`. Actual usage
was **56.3939 allocated core-hours**, including both pilots and rendering;
the forward allocations account for 56.3411 core-hours. This excludes the
previously completed, separately approved Day 480 campaign. Execution ran
from 02:27:07 to 06:15:18 America/New_York on 15 September 2026. Raw accounting
and its aggregation are saved in the run directory as
`execution_resources.csv` and `resource_summary.json`.

Initially each remaining array had concurrency 2. Once only one continuation
remained, the full-campaign array increased to 3; after all continuations
finished, it increased to 4. Combined concurrency never exceeded 4, and no
tasks or time limits were added. These changes are recorded in
`throttle_adjustment_3.json` and `throttle_adjustment_4.json`. `Project.toml`
and `Manifest.toml` are archived under `code/environment/` and matched the
pre-run hashes.

## Presentation

The compact layout contains three equal-aspect maps: permeability, pressure
difference `(p-p0)` in MPa and dimensionless CO2 saturation. It keeps the full
0–3200 m horizontal / 0–1600 m depth extent, positive down, and common injector.
The fixed permeability scale now matches the reference ensemble figure:
Colorcet rainbow4, 1–10000 mD, logarithmic. Values below 1 mD use the lowest palette
color, as in the reference; no scientific permeability values are changed.
The response panels retain 20%-opacity permeability overlays. All colorbars
share their baseline and dimensions; response scales are fixed across members.

Magenta perimeters mark exactly those cells where raw reservoir pressure is
greater than the spatially varying initial pressure plus 4 MPa. The label is
**Pressure-limit exceedance**. No new failure mechanism is introduced.

Exports are a compact 1920×600 MP4/PNG for slide embedding and a 1920×1080 MP4/PNG
containing the same compact content centered vertically, without distortion.
Both MP4s use H.264/yuv420p at 24 fps, 18 repeated display frames per member:
64 members, 1152 frames, 48 seconds. There is no interpolation between members.
Every frame compares the same member at exactly Day 1920.

The [Day 1920 pilot preview](../../../plots/DT_control/videos/joint_perm_day1920/pilot_preview_20260915/poster_compact.png)
shows the first predeclared member, position 1 / geological ID 741. Its area
with CO2 saturation ≥0.01 grew from 1.679% of the domain at Day 480 to 12.800%
at Day 1920. The region with pressure increase ≥0.1 MPa grew from 38.106% to
66.222%; maximum pressure increase at Day 1920 is 2.80346 MPa. These fixed
diagnostic levels describe this member's displayed extent, not an added
failure criterion. Both pilot members have zero Day 1920 pressure-limit
exceedances. The pilot preview uses only pilot-based response color limits.

## Final outputs and validation

All **64 predeclared members** completed and appear in the movies. Their
geological realization IDs and permeability hashes are all distinct. This
is a documented 64-member subset of the 128-position ensemble; the other
64 positions were outside the selection, not failed runs. The manifest
lists all 128 positions and their status. No selected member was omitted.

| Quantity | Fixed display limits |
|---|---|
| Permeability | 1–10000 mD, logarithmic, Colorcet rainbow4 |
| Pressure difference, p − p0 | −0.1–4.0 MPa |
| CO2 saturation | 0–1, dimensionless |

The memberwise maximum pressure increase ranges from **2.00703 to 3.91307 MPa**.
All 64 members have **zero pressure-limit exceedance cells at Day 1920**,
so no magenta exceedance boundaries appear in these final frames. Intermediate
checkpoints are not shown and should not be used to infer the final-time mask.
The domain fraction with CO2 saturation ≥0.01 ranges from **10.3012% to 13.6322%**.
This diagnostic level describes plume extent and is not a failure threshold.

Final checks confirmed identical initial pressure/saturation, porosity and
schedule hashes across all 64 members; matching geological IDs, input and
restart sources; and the same Day 1920 pressure/saturation fields within
each frame. Every frame passed text-boundary and aligned-colorbar checks.
The poster and a middle frame were also inspected visually. Both files
were fully decoded: **1152 frames, 24 fps, 48.0 seconds, H.264/yuv420p**,
at the intended resolutions, with output hashes verified.

- [Compact MP4 for slide embedding, 1920×600](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/joint_permeability_day1920_64_compact.mp4)
- [1080p MP4, 1920×1080](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/joint_permeability_day1920_64_1080p.mp4)
- [Compact PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/poster_compact.png)
- [1080p PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/poster.png)
- [Member provenance table](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/provenance.csv)
- [Caption](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/caption.txt)
- [Manifest, selection status and encoding checks](../../../plots/DT_control/videos/joint_perm_day1920/v2_64members_20260915/manifest.json)

Separate posterior mean/std slides retain their own interpretation; this
controlled permeability comparison does not attribute all posterior
uncertainty exclusively to permeability.

## Presentation revision: 32-second version

The subsequent presentation revision uses a larger, centered 30 pt main
heading and smaller 22 pt panel headings. Axis and colorbar labels are 19 pt,
ticks are 17 pt, and the method note and realization ID are 16 pt. The ID
is retained at the bottom right to allow matching individual frames to the
provenance table. The bottom-left note reads:
“Simulated with identical initial pressure/saturation and injection schedule.”

The revised duration is **32 seconds**, two-thirds of the previous 48 seconds:
all 64 members remain, each displayed for 12 frames / 0.5 seconds at 24 fps.
Only presentation and playback timing change. This revision reuses the same
saved Day 1920 fields, member order, color scales, overlays and well locations.
No additional forward simulations were needed. Previous exports remain
available in the `v2_64members_20260915` directory.

The rendering source snapshot is `code/render_v3_20260915/` within the run
directory; `render_v3_request.json` records its hashes and requested changes,
and `render_v3_job.json` records Slurm job `13233201`. The plotting scripts
passed syntax checks, and the single-frame preview passed clipping, title
centering, spacing and aligned-colorbar checks. The three map interiors in
that preview are pixel-identical to the previous poster.

Job `13233201` completed successfully in 87 seconds (0.0483 allocated
core-hours). Both exports fully decoded to 768 frames at 24 fps / 32 seconds
in H.264/yuv420p, with their intended resolutions and verified file hashes.
All 64 layouts passed the checks, and a final middle frame was inspected
visually. Every member's provenance row matches version 2 except for the
new frame PNG path; member order and all color limits also match. Results
are recorded in the run directory's `render_v3_validation.json`.

- [Revised compact MP4, 32 seconds](../../../plots/DT_control/videos/joint_perm_day1920/v3_64members_32s_20260915/joint_permeability_day1920_64_compact.mp4)
- [Revised 1080p MP4, 32 seconds](../../../plots/DT_control/videos/joint_perm_day1920/v3_64members_32s_20260915/joint_permeability_day1920_64_1080p.mp4)
- [Revised compact PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v3_64members_32s_20260915/poster_compact.png)
- [Revised provenance table](../../../plots/DT_control/videos/joint_perm_day1920/v3_64members_32s_20260915/provenance.csv)
- [Revised manifest](../../../plots/DT_control/videos/joint_perm_day1920/v3_64members_32s_20260915/manifest.json)

## Title spacing refinement

Version 4 moves the centered main heading down by 18 pixels, reducing the
bounding-box gap to the panel titles from 28.89 to 10.89 pixels. All pixels
below the heading band in the preview match version 3, including panel
titles, maps, axes, colorbars and the footer. The 64-member sequence still
lasts 32 seconds, with the same font sizes, fields and physical time.

The source snapshot is `code/render_v4_20260915/` in the run directory.
`render_v4_request.json` records the change and source hashes, and
`render_v4_job.json` records rendering job `13233839`.

The job completed successfully in 85 seconds. All 64 layouts passed, both
32-second videos decoded to 768 frames at 24 fps in H.264/yuv420p, and output
hashes were verified. Provenance, member order, panel bounds, font sizes and
color limits match version 3. The final poster matches the inspected preview.
The validation record is `render_v4_validation.json` in the run directory.

- [Version 4 compact MP4](../../../plots/DT_control/videos/joint_perm_day1920/v4_64members_32s_20260915/joint_permeability_day1920_64_compact.mp4)
- [Version 4 1080p MP4](../../../plots/DT_control/videos/joint_perm_day1920/v4_64members_32s_20260915/joint_permeability_day1920_64_1080p.mp4)
- [Version 4 PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v4_64members_32s_20260915/poster_compact.png)

## 24-second playback version

Version 5 retains the approved version-4 layout and all 64 members, with
each member displayed for 0.375 seconds (9 frames at 24 fps). The full movie
is 24 seconds / 576 frames. It uses the same archived version-4 renderer
with `--hold-seconds 0.375`, saved Day 1920 fields and fixed member order.
`render_v5_request.json` and `render_v5_job.json` in the run directory record
the source hashes and Slurm rendering job `13234782`.

The job completed successfully in 79 seconds. Both H.264/yuv420p exports
decoded to 576 frames / 24 seconds at 24 fps, with verified file hashes.
All 64 PNG frame hashes are identical to version 4, and provenance, member
order, layouts and color limits also match. Checks are recorded in the run
directory's `render_v5_validation.json`.

- [24-second compact MP4](../../../plots/DT_control/videos/joint_perm_day1920/v5_64members_24s_20260915/joint_permeability_day1920_64_compact.mp4)
- [24-second 1080p MP4](../../../plots/DT_control/videos/joint_perm_day1920/v5_64members_24s_20260915/joint_permeability_day1920_64_1080p.mp4)
- [Version 5 PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v5_64members_24s_20260915/poster_compact.png)

## Explicit title and initial conditions

Version 6 is titled **Permeability effects on pressure buildup and CO2
saturation at Day 1920**. The footer gives numerical initial conditions
instead of only saying that they are identical. It also states that the
comparison is at fixed time with the same injection schedule. The initial
condition values in the footer and caption are read from the saved input
arrays when rendering.

The actual common Day 0 fields, independently checked in
`members/001/inputs.jld2`, are:

- **Pressure:** `p0[i,j] = 62500*j Pa`, for vertical indices `j=1..256`.
  The initializer uses depths `z_j=6.25*j m`, equivalent to a water-hydrostatic
  gradient of **10 kPa/m** (`rho_water=1000 kg/m³`, initialization `g=10 m/s²`).
  The stored field spans **0.0625–16 MPa**, is uniform horizontally, and has
  **11.9375–12.3125 MPa** along the completed well cells. The footer summarizes
  the well pressure as approximately 12 MPa.
- **CO2 saturation:** exactly **0.3322826642865828 in 57 near-well cells**,
  and **zero in all other 131015 cells**. The small seeded patch occupies
  cells within x=1531.25–1587.5 m and depth=1162.5–1218.75 m, measured using
  displayed cell edges; it is not a filled rectangle. Water saturation is
  the complementary `1-S_CO2`.

This local initial CO2 patch comes from the fixed reconstruction of the
first monitoring step's member-1 initialization with seed 2025. All 64
permeability members share it, as confirmed by the input hashes. It is an
inherited initial condition, not CO2 newly injected during the displayed
forward comparison. The clarification changes presentation only and uses
the same simulation results and 24-second playback.

The run directory contains `initial_conditions_audit_20260915.json` with
the exact values, source-file hash, field hashes, patch extent and seed.
The renderer snapshot is `code/render_v6_20260915/`; request and job records
are `render_v6_request.json` and `render_v6_job.json` (Slurm `13245061`).

The rendering job completed successfully in 77 seconds. All 64 frames
passed text, title-spacing and colorbar checks and reported the same exact
initial conditions. Both exports fully decoded to 576 frames / 24 seconds
at 24 fps in H.264/yuv420p; hashes were verified. Member provenance matches
version 5, and the final poster matches the inspected preview. Its panels,
axes and colorbars are pixel-identical to version 5. These checks are saved
as `render_v6_validation.json` in the run directory.

- [Version 6 compact MP4](../../../plots/DT_control/videos/joint_perm_day1920/v6_explicit_initial_conditions_24s_20260915/joint_permeability_day1920_64_compact.mp4)
- [Version 6 1080p MP4](../../../plots/DT_control/videos/joint_perm_day1920/v6_explicit_initial_conditions_24s_20260915/joint_permeability_day1920_64_1080p.mp4)
- [Version 6 PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v6_explicit_initial_conditions_24s_20260915/poster_compact.png)

## Version 7: remove the on-screen footer

At the user's request, version 7 removes the method sentence and realization
ID from the video. The user will place the method sentence on the slide.
Member IDs remain in the external provenance table. The 64 members, fixed
Day 1920 fields and 24-second playback are retained.

The preview's entire region above the removed footer is pixel-identical to
version 6, including the title, three panels, axes and colorbars. The source
snapshot is `code/render_v7_20260916/` in the run directory; request and job
records are `render_v7_request.json` and `render_v7_job.json` (Slurm `13247632`).

The job completed successfully in 78 seconds. All 64 PNG frames have a
blank footer, and the layout records confirm that neither the method note
nor the realization ID is displayed. The provenance rows and member order
match version 6. Both H.264/yuv420p videos fully decoded to 576 frames at
24 fps / 24 seconds, with verified hashes. The final poster matches the
inspected preview. Checks are recorded in `render_v7_validation.json`.

- [Version 7 compact MP4](../../../plots/DT_control/videos/joint_perm_day1920/v7_no_footer_24s_20260916/joint_permeability_day1920_64_compact.mp4)
- [Version 7 1080p MP4](../../../plots/DT_control/videos/joint_perm_day1920/v7_no_footer_24s_20260916/joint_permeability_day1920_64_1080p.mp4)
- [Version 7 PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v7_no_footer_24s_20260916/poster_compact.png)

## Version 8: trim the bottom whitespace

The compact canvas is now **1920×552**, trimming 48 unused bottom pixels
and leaving approximately 8 pixels below the lowest colorbar-label content.
The preview is pixel-identical to the top 552 rows of version 7. Title,
panels, axes, colorbars and fonts keep their existing pixel positions and
sizes. The 64-member sequence remains 24 seconds.

Use the compact MP4 for slide embedding. A 1920×1080 master is also exported
with the same content centered vertically, retaining the padding required
by its different aspect ratio. The source snapshot is `code/render_v8_20260916/`
in the run directory; request and job records are `render_v8_request.json`
and `render_v8_job.json` (Slurm `13247846`).

The job completed successfully in 71 seconds. All 64 PNG frames are exactly
pixel-identical to version 7 after removing its bottom 48 rows. All layout
and clipping checks passed. Both H.264/yuv420p videos decoded to 576 frames
at 24 fps / 24 seconds at the intended resolutions, and file hashes were
verified. Provenance and member order match version 7. Validation is saved
in `render_v8_validation.json` in the run directory.

- [Version 8 compact MP4, trimmed for slides](../../../plots/DT_control/videos/joint_perm_day1920/v8_tight_bottom_24s_20260916/joint_permeability_day1920_64_compact.mp4)
- [Version 8 compact PNG poster](../../../plots/DT_control/videos/joint_perm_day1920/v8_tight_bottom_24s_20260916/poster_compact.png)
- [Version 8 padded 1080p master](../../../plots/DT_control/videos/joint_perm_day1920/v8_tight_bottom_24s_20260916/joint_permeability_day1920_64_1080p.mp4)
