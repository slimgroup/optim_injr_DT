# Compact layout and proposed 64-member Day 1920 comparison

Status: **layout preview complete; new simulation scope and budget awaiting
user confirmation. No new forwards submitted.**

## Completed visual correction

The previous movie used Colorcet `rainbow4` with log10(mD) limits −3 to 4.
The supplied permeability-ensemble figure uses the same palette with limits
0 to 4, equivalent to 1–10000 mD. The compact preview now matches that mapping,
including its palette-endpoint clipping below 1 mD. The permeability arrays
are unchanged. All three horizontal colorbars share width, height and baseline.

The new preview removes the large title, injection-rate array, control notes
and explanatory footer. It keeps the three panel names, units, a fixed-day
label and geological realization ID. Pressure is still `(p-p0)` in MPa, and
both response panels retain the 20%-opacity permeability overlay. Full grid
extent, depth direction, well and equal physical aspect are preserved.

[Compact PNG preview](../../../plots/DT_control/videos/joint_perm_day480/compact_preview_v2b_20260915/poster_compact.png)
is 1920×600, intended to use the width of the slide's image region. It contains
the actual saved **Day 480 / ID 741** result. It is not a Day 1920 prediction.
The original 1920×1080 movie remains available; the compact aspect is an
additional slide asset. The preview was visually inspected and its text
boundaries, adjacent tick separation and colorbar alignment checked.

For this displayed member at Day 480, cells with CO2 saturation ≥0.01 occupy
1.679% of the full domain; cells with pressure increase ≥0.1 MPa occupy 38.106%.
These are explicit visualization diagnostics for one member, not failure
thresholds or ensemble statistics. Pressure propagates over a much wider
region than the visibly high-saturation plume.

## Proposed physical experiment

Show 64 distinct permeability realizations at one fixed **Day 1920**. Preserve
the existing 32 members, add 32 using only ensemble indices and duplicate-ID
checks, and retain identical initial pressure/saturation, well, grid, fluid
properties, porosity and boundary treatment across all members. The exact
selection is frozen in [member_plan.csv](member_plan.csv) and
[proposal.json](proposal.json); no pressure or saturation outcome is used to
choose added members.

Use the existing selected PoF epsilon=0.01 campaign schedule, unchanged:

| Days | Six consecutive 80-day rates, m³/s |
|---|---|
| 0–480 | 0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530 |
| 480–960 | 0.04530, 0.05087, 0.05645, 0.06203, 0.06760, 0.07317 |
| 960–1440 | 0.07317, 0.07458, 0.07599, 0.07741, 0.07882, 0.08023 |
| 1440–1920 | 0.08023, 0.08041, 0.08059, 0.08078, 0.08096, 0.08114 |

The 24 rates were read directly from
`plots/paper_figures/forward_sim_four_steps_base_data.jld2::POF_eps0p01_rates`
and agree with Case 2 of steps 1–4 in `docs/injection_rate_arrays.md`.
The multiplier is exactly 1, and the first six rates equal the existing
Day 480 experiment. The proposed cumulative scheduled injection volume is
10.543 times the first-interval volume. Plume growth is plausible, but its
extent and pressure distribution must be obtained from the actual forwards.

This replays the same preselected control schedule for every realization;
there are no posterior-state replacements or new optimizations at monitoring
boundaries. The movie still compares realizations at a single time. It is
not a time-lapse and does not attribute posterior uncertainty exclusively to K.

## Missing data and execution budget

No matching Day 1920 ensemble fields were found in the inspected available
outputs. Existing full-campaign ground-truth fields are ID 2000 with initial
saturation amplitude 0.5 and a permeability-dependent well location. They
do not match this experiment's common initial saturation amplitude
0.3322826642865828, fixed well and selected geological IDs.

| Work | Tasks | Per-task allocation | Maximum allocated core-hours |
|---|---:|---|---:|
| Continue saved 32 members, Day 480→1920 | 32 | 4 CPUs, 16 GiB, 60 min | 128 |
| Added 32 members, Day 0→1920 | 32 | 4 CPUs, 16 GiB, 90 min | 192 |
| Render and validate 64-frame movie | 1 | 2 CPUs, 8 GiB, 15 min | 0.5 |
| Total | 65 | At most four simultaneous forwards | **320.5** |

The 32 existing endpoints will be reused. There are 1344 new 80-day simulation
periods, plus one pilot replay of period 6 from a saved Day 400 checkpoint to
verify pressure/saturation restart consistency against the saved Day 480
result. That replay fits within its pilot task's allocation. The first two
pilot members are existing position 1 and added position 3. Continue only
after their state, schedule and field checks pass; retain and report failures.

Based on the 32 completed Day 480 jobs and existing ground-truth full-campaign
timings, approximately 55–105 allocated core-hours and 4–7 elapsed hours at
concurrency four are expected, excluding queue time. These are estimates,
not guarantees. The maximum allocation is 320.5 core-hours. Checkpoints and
inputs are estimated at about 3.5 GiB. No historical outputs are overwritten.

The proposed movie holds each member for 0.75 seconds: **64 members, 48 seconds**.
All panels use the same member and Day 1920, with fixed color limits across
all members. K uses 1–10000 mD; saturation uses 0–1. Pressure color limits are
set once after inspecting all completed fields. The original cellwise test
`p_res[i,j] > p0[i,j] + 4e6 Pa` is retained, with the label
**Pressure-limit exceedance**. No schedule or threshold will be changed to
make the movie more dramatic.

Confirmation is required by item 3 of the user's original video request:
additional forward runs require a missing-data list and runtime/job budget
for approval. The previous approval covered 32 members through Day 480;
this proposal changes both member count and physical comparison time.
