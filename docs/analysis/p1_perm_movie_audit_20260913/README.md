# Joint permeability / pressure / saturation movie — audit and approval request

Target slide: `p1-perm-movie`, now page 10. Audit: 13 September 2026.

**No qualifying ensemble movie can be made from the inspected historical outputs.**
All 128 ensemble positions lack a verified pressure/saturation pair at Day 480
under the selected common schedule, common initial state and fixed well geometry.
No new forward simulation or optimization was submitted. No MP4 or PNG poster
has been produced; an unrelated truth or posterior field has not been substituted.

## What exists, and why it is insufficient

| Historical source | Finding | Reuse decision |
|---|---|---|
| `data/geo/wise_perm_models_2000_new.jld2`, `BroadK` | 2000 permeability arrays; Julia `(2000,512,256)`, Float32 mD. | Valid permeability source. |
| `data/state/{new,old}/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2`, `idx_t1` | The two index arrays agree exactly: 128 positions, **125 distinct IDs**. | Use these IDs; never relabel a position as a geological realization ID. |
| Same state files, `state128_t1`, `inj_t1` | HDF5 shapes `(1572864,128)` and `(128,)`; `inj_t1` is an integer depth index (191–200), not an injection-rate schedule. No complete common-state/common-schedule/time provenance is embedded. | Do not infer a qualifying forward experiment from the state-array dimensions. |
| Step-1 `POF__HARD__eps=0.01__.../sample={1:128}/final.jld2` | All 128 finals exist; **none contains pressure or saturation field keys**. Their optimized schedules differ. Their saved commits use seed `2025+s-1`, a member-dependent saturation blob and a permeability-dependent well depth. | Cannot isolate permeability or recover the missing fields. |
| `plots/paper_figures/forward_sim_four_steps_base_data.jld2` | Correct unscaled PoF epsilon=0.01 schedule and Day 480 fields exist, but only for **truth ID 2000**, which is absent from the 128-member ensemble. | No substitution. |
| `plots/paper_figures/full_campaign_video_POF_eps001.jld2` | Also contains the correct schedule and truth-ID-2000 Day 480 fields, saved at eight-day intervals. | Same exclusion. |
| Ground-truth initial state | Forward generators use a fixed saturation blob of **0.5**, centered at depth index **192**. Step-1 optimization uses a seeded blob and member-dependent location. The old exports do not store their initial state/hash. | Cannot certify equality with the desired ensemble initial states. |
| `plots/paper_figures/forward_sim_data.jld2` | No `POF_eps0p01` fields. The saved PoF-epsilon-zero rates end at **0.05082**, while the current script describes another scaled ramp. | Actual saved values take precedence over comments/current source; reject this asset. |
| `plots/DT_control/videos/128perm/video_128perm_*/128_permeability_samples.mp4` | Eight historical permeability-only videos, no simulated pressure/saturation panels. | Does not meet the joint-field requirement. |
| Five-case and sensitivity videos / day-728 exports | Truth-only, policy/time comparisons and/or multiplied schedules. | Excluded. |
| Posterior exports and mean/std figure arrays | Observation-conditioned state uncertainty, without the required common initial state. | Excluded; never attribute this uncertainty exclusively to permeability. |
| Zero-injection diagnostics | All-brine initialization with disabled injection; long pilot windows did not complete, and completed fields stop at eight days. | State/trajectory mismatch. Only the previously exported **permeability binaries** are reused for this audit. |

The filename census contains 6,706 JLD2 files under `data/`, 38 under `plots/`
and 112 archived JLD2 files. Scratch `~/scratch/optim_injr_DT` contains no JLD2
files. The census is in [historical_jld2_paths.txt](historical_jld2_paths.txt).
Content inspection focused on all 128 relevant optimization finals, all 38 paper
forward exports, first-step state metadata, initialization/source code and prior
diagnostic records; it did not deserialize every unrelated optimization case.
No external Compass repository or original observation-generation manifest is
available in this workspace, so no cross-repository provenance is claimed.

Duplicate geological IDs are 734 (positions 62,69), 1011 (72,83) and 960
(101,115). A full version would retain **128 ensemble positions / 125 distinct
permeability IDs**, allowing a verified identical forward result to serve both
positions in each duplicate pair. Repeated IDs are not failed or missing members.

The 128 finals have eight saved commit stamps, one marked `-dirty`; the exact
stamps and member mapping are in [members.csv](members.csv). All eight available
base commits contain the same member-specific seed/blob/well-selection logic;
see [historical_source_checks.json](historical_source_checks.json). A dirty
working tree cannot be reconstructed exactly from its base commit. The historical
initial-state hashes in the table are explicitly **code reconstructions**, not
hashes read from saved historical initial states. All 128 reconstructed saturation
hashes differ. This alone precludes assuming a shared historical state.

## Fixed schedule and model settings

The selected historical Step-1 PoF epsilon=0.01 rates are

```text
[0.00010, 0.00914, 0.01818, 0.02722, 0.03626, 0.04530] m3/s
```

Each rate lasts 80 days; six periods end at Day 480. These are the arrays actually
used historically, from `docs/injection_rate_arrays.md` and the saved base export.
The later ECDF-grid correction is not a replacement input. No multiplier is used.

| Setting | Value |
|---|---|
| Grid and cell dimensions | 512 × 1 × 256; 6.25 × 100 × 6.25 m; top depth 0 m |
| Figure cell-edge extent | x: 0–3200 m; depth: 0–1600 m, positive down |
| Permeability | mD; simulation conversion 9.86923266716013e-16 m²/mD; Kz/Kx=0.36, Ky=Kx |
| Initial pressure | `p0[ix,iz] = 1000*10*(iz*6.25)` Pa, Julia iz=1:256; preserve the inherited numerical datum |
| Porosity/boundary treatment | Interior 0.25; `pad=true`: x sides and bottom set to 1e8, then top row overwritten to 0.25 at h=0; no added cells or new external pressure boundary |
| External faces | Closed finite-volume external faces; high-storage padding retained |
| Fluid properties | CO2/brine reference densities 700/1000 kg/m³, viscosities 1e-4/1e-3 Pa·s, compressibilities 1e-9/1e-11 Pa⁻¹, PVT reference 15 MPa |
| Relative permeability | Brooks–Corey exponents [2,2], residual saturations [0.1,0.1], endpoint 1 |
| Software inspected | Julia 1.11.3; Jutul 0.2.11, JutulDarcy 0.2.7, JutulDarcyRules 0.2.8 |
| Pressure limit | **Cellwise** `p_res[ix,iz] > p0[ix,iz] + 4e6` Pa |
| Pressure/saturation display | Reservoir pressure in MPa, CO2 saturation dimensionless |

The inherited initialization uses gravity 10 m/s² while the solver uses
9.80665 m/s². Preserve this setup for comparability; the movie request does not
authorize a numerical-equilibrium repair. Well connection factors necessarily
respond to permeability, but well location/completion geometry must remain fixed.

Day 480 in the base export is `POF_eps0p01_{pres,sat}_snaps`, Julia snapshot 6
(Python index 5); its saved substep is 60. In the full video export it is
`{pres,sat}_all`, Julia output 60 (Python index 59). The former is Float64 and the
latter Float32: their maximum differences are 0.500 Pa and 2.98e-8 saturation.
These are two exports of the truth experiment, not two ensemble members.
The base truth snapshot has zero pressure-limit exceedance cells. It is not used
to select or tune a more dramatic schedule.

## Proposed new controlled experiment — requires approval

Freeze the **reconstructed first-step ensemble position 1** initial state and
well for every realization: seed 2025, nonzero blob value
`0.3322826642865828`, Julia well start `(250,1,191)`, nominal coordinates
`(1562.5,100,1193.75)` m and end depth 1231.25 m. The completion spans seven
cells, z indices 191–197. Plot its actual cell-center x=1559.375 m and depths
1190.625–1228.125 m consistently in all panels. Common pressure is the inherited
hydrostatic array above. Reusing this state for the other members is an explicit
new controlled comparison, not a claim that the old ensemble had identical states.

Proposed numeric SHA-256 values (Float64 little endian, z,x C order, equivalent
to Julia x,z column-major serialization):

| Common array | SHA-256 |
|---|---|
| Initial pressure | `8e8b73991720afddc6c93f12f3cf95be35085d4275972b36917b0a4d26cb6ea7` |
| Initial CO2 saturation | `693eedb0364b5dc535271a51d23118253615144bc41fa8bd0fcfb88131e1a8a4` |
| Porosity including padding | `7e1a48200e2c665bb3ecdf0b3bee7d982af79a751161a9a5986557cf2efc3ac9` |
| Pressure limit | `49f25b842c9694f74a1b4111075bccc7e8629b75347277f4abb7d003efed0661` |

Before forward execution, verify these hashes from the actual simulator input
arrays and verify every selected permeability cache against the original BroadK
slice on a compute node. The audit rechecked all 128 cached binary hashes and
the current index mapping; it did not rehash the original 2 GB geological file.
Cache origin and the earlier source-file hash are recorded in [audit.json](audit.json).
The zero-injection diagnostic saturation/pressure trajectories are not reused.

**Recommended talk version:** 32 positions selected by
`rint(linspace(1,128,32))`, with 0.75 seconds per position, total **24 seconds**.
The selected IDs are distinct. This rule was fixed before any new forward outcomes:

```text
Positions: 1,5,9,13,17,21,26,30,34,38,42,46,50,54,58,62,
           67,71,75,79,83,87,91,95,99,103,108,112,116,120,124,128
IDs:       741,732,312,1593,697,133,76,1266,1280,1956,584,67,1503,121,234,734,
           130,177,1668,1141,1011,1949,1787,484,833,1616,940,1666,222,1237,1845,1542
```

All 128 positions are presently missing matched forward fields. The talk version
would intentionally omit the 96 positions outside this fixed subset; they are
not classified as failures. Start with subset positions **1,62,128** (IDs
741,734,1542) as a three-member pilot. Only continue after all three reach Day 480
with finite fields and matching fixed-input hashes. Retain all failures and logs;
do not replace a failed member with a visually convenient one.

| Approval scope | Slurm resources | Maximum allocated core-hours |
|---|---|---:|
| Three-member pilot only | 3 tasks × 4 CPUs × 16 GiB × 1 hour | 12 |
| Complete 32-member talk version, including pilot | 32 tasks, same per-task resources, at most 4 concurrent | 128 |
| Optional full ensemble, including pilot | 125 unique forwards, same resources, at most 4 concurrent | 500 |
| Rendering, after successful forwards | 2 CPUs, 8 GiB, 15 minutes | 0.5 |

These are hard allocation caps, **not measured ensemble runtime predictions**.
For scale, truth-only PoF 1920-day job `9820154_0` / `9820157` used 26m39s
and about 3.9 GiB; replay job `12902263_1` / `12902267` used 18m02s and about
2.2 GiB. They do not establish performance for heterogeneous members under the
new common initial state. A different all-brine/zero-injection pilot timed out
at 45 minutes; it is not a timing benchmark for the requested injection run.
At full time limits and concurrency four, the talk allocation spans up to nine
hours including the separate pilot gate, plus queueing/rendering. The full
allocation spans up to 32 hours plus queueing/rendering. Stop on pilot failure
or budget exhaustion and report before any extension.

Final Float64 pressure+saturation storage is 2 MiB per distinct member: 64 MiB
for 32 or 250 MiB for 125, excluding input copies, checkpoints, logs and frames.
Only the Day 480 field is needed for the movie; there is no request for BHP export.

## Video delivery contract after approval

One three-panel frame per selected realization, synchronized K/p/S at Day 480.
Show geological realization ID and ensemble position distinctly; display
**“Day 480, fixed time; permeability varies”** once per frame. Use aligned
cell-edge extents, positive-down depth, consistent well geometry and equal panel
sizes. Label permeability in mD with log scaling, reservoir pressure in MPa and
saturation dimensionless. Use common positive log color limits covering the
selected permeability fields, common pressure extrema across all completed
approved members, and saturation [0,1]. Final numeric K/p limits remain pending
until the appropriate fields have been validated; no placeholder pressure limits
are asserted as final.

Outline/hatch the exact Boolean cell mask `p_res > p0+4e6`, including cells at
domain edges. Label it **“Pressure-limit exceedance”**. Do not replace the
spatially varying limit with an absolute-pressure contour. Export 1920×1080
H.264/yuv420p MP4 at 24 fps: hold each member for 18 identical frames, with no
crossfade or interpolation between physical states. Export a PNG poster from
the first selected member, not from a pressure extreme. A full version is
96 seconds for 128 positions and must disclose its three repeated IDs.

Save in a new job-specific directory under `data/` and a new
`plots/DT_control/videos/joint_perm_day480/` directory. Preserve every historical
output. The final per-member provenance table must contain actual run IDs,
initial/input checks, field paths and hashes, time, rate source, units, numeric
color limits and failed/omitted member status. The current [members.csv](members.csv)
is a **missing-data audit**, not a completed-movie provenance claim.

Proposed caption, valid only after successful completion:

> Permeability-driven variability in reservoir pressure and CO2 saturation at
> Day 480 under the selected PoF epsilon=0.01 injection schedule. Initial pressure
> and saturation, injection schedule, well geometry and all other model settings
> are held fixed. Outlines identify cells above the model pressure limit
> p0(x,z)+4 MPa. The 32 positions were selected uniformly from the 128-member
> first-step ensemble; frames compare realizations, not successive times.

The separate posterior mean/std slides concern uncertainty after conditioning
on observations and must retain that interpretation.

## Reproduce the input audit

The audit script only reads historical inputs and writes a **new** directory.
It does not run forward simulations or submit jobs. The Julia invocation below
only evaluates 128 seeded scalar random values; it performs no simulation.

```bash
module load julia/1.11.3
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
movie_seed_file=$(mktemp /tmp/p1_movie_seeds.XXXXXX)
julia --startup-file=no -e 'using Random; for s in 1:128; Random.seed!(2025+s-1); println(s, ",", 0.2+rand(Float64)*0.6); end' > "$movie_seed_file"
OPENBLAS_NUM_THREADS=1 python scripts/python_tools/analysis/audit_joint_permeability_movie.py \
  --seed-amplitudes "$movie_seed_file" \
  --output docs/analysis/p1_perm_movie_audit_NEW_DIRECTORY
```

The source checks are retained separately in `historical_source_checks.json`.
This script audits the historical sources enumerated here; newly supplied
Compass exports require a new provenance review before an eligibility decision.
The local audit passed its index, binary hash, schedule, time and threshold-array
assertions. Slurm was checked outside the sandbox after its known sandbox
controller error; no jobs for this user were active at the audit check.
