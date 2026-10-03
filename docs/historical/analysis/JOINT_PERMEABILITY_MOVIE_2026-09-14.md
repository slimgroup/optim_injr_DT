# Joint permeability, pressure increase and CO2 saturation — first version

Target slide: `p1-perm-movie`. The user approved new forwards and the proposed
32-member subset on 14 September 2026, then requested three horizontal panels,
pressure difference relative to initial hydrostatic water pressure, and faint
permeability overlays in the pressure and saturation panels.

## Experiment and saved inputs

This is a new controlled forward comparison at **Day 480**, not a time-lapse or
posterior-sample movie. The selected historical PoF epsilon=0.01 schedule is
`[0.00010,0.00914,0.01818,0.02722,0.03626,0.04530]` m3/s, six 80-day periods,
without a multiplier. No optimization is run. The initial pressure and CO2
saturation are identical across members, as are well geometry, grid, porosity,
boundary treatment, fluid properties and requested output intervals.

The common state is the reconstructed first-step ensemble position 1 state,
seed 2025, with saturation-blob amplitude 0.3322826642865828. The injector is
fixed at Julia `(250,1,191)` through `(250,1,197)`, independently of permeability.
Pressure initialization is `p0[ix,iz]=1000*10*(iz*6.25)` Pa. This deliberately
does not reuse the original member-dependent seeded saturation states. The
audit and approval proposal are retained in
[the input audit](../../analysis/p1_perm_movie_audit_20260913/README.md).

Successful run directory:
`data/forward_comparisons/joint_perm_day480_20260915T031220Z_attempt2/`.
Each member has `inputs.jld2`, six `period_XX.jld2` checkpoints and, on success,
`day480.jld2` plus `COMPLETE.txt`. Only `day480.jld2` fields enter the movie.
No BHP analysis/export is part of this work.

`inputs.jld2` includes the actual simulator initial arrays, permeability in mD,
porosity including padding, the cellwise pressure limit and the fixed well/rates.
Every member's authoritative `BroadK[idx,:,:]` slice is checked against its
previously audited Float32 binary SHA-256 before simulation. Final pressure and
saturation are saved in Float64 and hashed. Python independently verifies their
hashes, actual initial arrays, schedule, geometry and time before rendering.

Common hashes (Float64 little endian, Julia x,z column-major, equivalent to
Python z,x C-order):

| Array | SHA-256 |
|---|---|
| Initial reservoir pressure | `8e8b73991720afddc6c93f12f3cf95be35085d4275972b36917b0a4d26cb6ea7` |
| Initial CO2 saturation | `693eedb0364b5dc535271a51d23118253615144bc41fa8bd0fcfb88131e1a8a4` |
| Porosity including padding | `7e1a48200e2c665bb3ecdf0b3bee7d982af79a751161a9a5986557cf2efc3ac9` |
| Cellwise pressure limit | `49f25b842c9694f74a1b4111075bccc7e8629b75347277f4abb7d003efed0661` |

## Fixed member selection

The 32 positions were fixed before new outcomes using
`rint(linspace(1,128,32))`. All 32 selected geological IDs are distinct. The full
historical ensemble contains 128 positions but 125 distinct geological IDs;
this version deliberately uses a subset, not all 128 positions. The remaining
96 positions are omitted by the fixed selection rule, not by pressure outcome.

```text
Positions: 1,5,9,13,17,21,26,30,34,38,42,46,50,54,58,62,
           67,71,75,79,83,87,91,95,99,103,108,112,116,120,124,128
IDs:       741,732,312,1593,697,133,76,1266,1280,1956,584,67,1503,121,234,734,
           130,177,1668,1141,1011,1949,1787,484,833,1616,940,1666,222,1237,1845,1542
```

## Execution and budget

| Job | Purpose | Outcome |
|---|---|---|
| `13208915` | Original 3-member startup | Failed before simulation because exported `Pressure` names collided. Outputs and errors retained in the original run directory. |
| `13208952` | Corrected 3-member pilot, positions 1,62,128 | All reached Day 480 and passed independent input/field checks. Wall times 5m13s, 5m41s, 5m10s. |
| `13209012` | Remaining 29 approved positions, concurrency at most four | All 29 completed and passed independent input/field checks. |
| `13209025` | Dependent 32-member movie rendering | Completed in 48 seconds; all 576 encoded frames decoded successfully. |

The startup fix qualified `JutulDarcyRules.Pressure/Saturations` and imported
other Jutul modules without introducing conflicting exports. It did not change
model inputs. The original failed attempt is preserved under
`data/forward_comparisons/joint_perm_day480_20260915T031220Z/`.
Retry pilots were reduced to a 55-minute limit; remaining tasks retain a
60-minute limit, 4 CPUs and 16 GiB, at most four concurrent. Rendering receives
2 CPUs, 8 GiB and 15 minutes. Even at every remaining limit, the total including
startup failures is 127.77 allocated core-hours, below the approved 128.5 cap.
Actual Slurm allocation use was **10.85 core-hours**, including the three
failed startup tasks, all 32 successful forwards and rendering. The raw
accounting record and calculated totals are retained in
`execution_resources.csv` and `resource_summary.json` in the successful run
directory. These are allocated CPU-hours, not measured CPU utilization.

## Presentation rendering

The three columns are **Permeability**, **Pressure difference** and
**CO2 saturation**. Pressure difference is `(p_res-p0)/1e6` MPa; the simulation
and exceedance comparison always retain the raw reservoir pressure in Pa.
The Boolean exceedance mask is computed cell by cell as `p_res > p0+4e6`.
Its exact cell perimeter, including exterior-domain edges, is drawn in magenta
and labeled **Pressure-limit exceedance**.

Color maps match the established repository palette: Colorcet `rainbow4` for
log permeability, Colorcet `CET_L3_r` for pressure difference, and CMasher
`rainforest_r` for saturation. A 20%-opacity permeability texture is composited
over both response maps. The colorbars represent the underlying scalar maps;
the texture is contextual and its opacity does not change data or the mask.
The three horizontal colorbars have identical baseline, width and height,
and align with the corresponding map axes.

All maps use the complete cell-edge extent x=0–3200 m, depth=0–1600 m,
positive down, and equal physical aspect. The well is drawn at actual reservoir
cell-center coordinates. Titles, tick labels, legends and colorbar labels are
checked against the canvas bounds. Numeric color limits are determined once
from all displayed members and stored in the final `manifest.json`; saturation
uses [0,1], and the log-permeability range includes the low-permeability caprock.

MP4 specification: 1920×1080, H.264, yuv420p, 24 fps. Each member is held for
18 frames (0.75 s), yielding 576 frames / 24 seconds for 32 members. Changes
are hard cuts with no interpolation. Every encoded frame is decoded for
validation. The poster is the first predeclared member, never an extreme chosen
after seeing outcomes.

## Outputs and final validation

Initial one-member layout preview:
`plots/DT_control/videos/joint_perm_day480/preview_member001_v1_20260915/poster.png`.
It uses actual Day 480 fields for position 1 / geological ID 741; its color
limits are preview limits, not the final 32-member limits.

Final target directory:
`plots/DT_control/videos/joint_perm_day480/v1_32members_20260915/`.
It contains the MP4, PNG poster, 32 PNG frames, caption, per-member provenance
CSV, manifest, encoding command and decoded-frame checksums.

Completed on 15 September 2026. All 32 selected members have valid Day 480
fields and identical initial pressure/saturation hashes. No selected member
is missing or omitted because of its simulated outcome. Fixed color limits
across all frames are permeability 0.001–10000 mD (log scale), pressure
difference −0.1–4.0 MPa, and dimensionless CO2 saturation 0–1. All 32 frames
passed text-boundary and colorbar-alignment checks; the final poster was also
visually inspected. The final MP4 is 1920×1080, H.264, yuv420p, 24 fps and
24 seconds, with 576 successfully decoded frames.

There are **zero pressure-limit-exceeding cells at Day 480 in all 32 selected
members**, so no magenta exceedance perimeter appears. This statement applies
only to the displayed time and selected members. The original cellwise limit
and selected schedule were preserved; no schedule was adjusted to create
exceedances.

Deliverables:

- [MP4](../../../plots/DT_control/videos/joint_perm_day480/v1_32members_20260915/joint_permeability_day480_v1.mp4)
- [PNG poster](../../../plots/DT_control/videos/joint_perm_day480/v1_32members_20260915/poster.png)
- [Caption](../../../plots/DT_control/videos/joint_perm_day480/v1_32members_20260915/caption.txt)
- [Per-member provenance table](../../../plots/DT_control/videos/joint_perm_day480/v1_32members_20260915/provenance.csv)
- [Manifest, including all 128 positions and subset omissions](../../../plots/DT_control/videos/joint_perm_day480/v1_32members_20260915/manifest.json)

The separate posterior mean/std slides retain their observation-conditioned
uncertainty interpretation; the new controlled comparison makes no claim that
their uncertainty is exclusively caused by permeability variation.
