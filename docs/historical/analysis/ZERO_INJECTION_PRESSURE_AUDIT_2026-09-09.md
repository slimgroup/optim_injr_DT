# Prospective zero-injection pressure-limit audit — 9 September 2026

The three-member pilot did **not complete either requested 480- or 960-day window**. All three jobs reached their 45-minute allocation limit. A separate eight-day diagnostic completed for one preselected realization, with exactly zero surface injection and CO2 saturation. Its maximum pressure increase was **38,825 Pa (0.038825 MPa)**, confined to the top row and equal to the inherited pressure-floor correction. All three candidate limits passed that short diagnostic. This does not establish their behavior over 480/960 days or distinguish an optimal limit.

Historical optimization runs, selected injection schedules, paper figures and the BHP audit were preserved. New files are under [the dated diagnostics directory](../../../data/diagnostics/zero_pressure_2026-09-09), [dated plots](../../../plots/diagnostics/zero_pressure_2026-09-09) and [retained Slurm logs](../../../logs/zero_pressure_2026-09-09/zero_pressure_2026-09-09). **The full 128-member batch was not submitted.**

## Configuration and provenance

The first-step ensemble is `BroadK` in `data/geo/wise_perm_models_2000_new.jld2`, selected by `idx_t1` in `data/state/new/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2`. The old and new index files agree. The 128 positions contain **125 unique realization IDs**; duplicates are retained. The complete mapping, binary input hashes and predeclared selection are in [members.csv](../../../data/diagnostics/zero_pressure_2026-09-09/members.csv). Pilot positions **1, 64, 128**, corresponding to IDs **741, 180, 1542**, were frozen before inspecting outcomes. None is the reference realization 2000.

| Setting | Retained production configuration |
|---|---|
| Permeability | Float32 mD; multiply by 9.86923266716013e-16 for m²; Kx=Ky, Kz=0.36 Kx |
| Grid | 512 × 1 × 256 cells; 6.25 × 100 × 6.25 m; top depth 0 m |
| Porosity | 0.25; stored geological `phi` is unused by production |
| Padding | x-side and bottom porosity 1e8; top reset to 0.25, including corners; 1,020 modified cells, no added cells |
| Initial pressure | p0=1000 × 10 × iz × 6.25 Pa, with one-based iz; no atmospheric offset |
| Gravity | Solver 9.80665 m/s²; initialization uses 10 m/s² |
| CO2 / brine | Reference densities 700 / 1000 kg/m³; viscosities 1e-4 / 1e-3 Pa·s |
| Compressibility | CO2 / brine: 1e-9 / 1e-11 Pa⁻¹, exponential density about 15 MPa |
| Relative permeability | Brooks–Corey exponents 2, residual saturations 0.1, endpoints 1 |
| Boundaries | Closed external faces; no prescribed reservoir sources or boundary forces; production storage padding retained |
| Outputs | Every 8 days; production 80-day simulator-call boundaries retained |

Execution used Julia 1.11.3, Jutul 0.2.11, JutulDarcy 0.2.7, JutulDarcyRules 0.2.8 and JLD2 0.4.55 from the shared depot. Repository HEAD was `c0c375257ed02833dd9d2144424c7a62ba6931b4`, with the preexisting dirty working tree recorded. Representative historical first-step PoF and CVaR records have commits `3b89f2ed843bec2e9e15cb9794479ab417561bca` and `646687876cf0b7d28ac7bf47d60bf3a6a8c15b16-dirty`, respectively; their three flow-package versions match. This is not certification of every historical run. The original Compass extraction/preprocessing commit was not recovered.

The [original manifest](../../../data/diagnostics/zero_pressure_2026-09-09/provenance_manifest.json) contains whole-input SHA256s, dependency tree hashes, source hashes and configuration. The [execution manifest](../../../data/diagnostics/zero_pressure_2026-09-09/execution_manifest.json) identifies actual runtime source snapshots, final analysis scripts and output hashes. [Source/input integrity checks](../../../data/diagnostics/zero_pressure_2026-09-09/input_source_integrity.csv) verify that hashed preexisting inputs and sources were preserved.

Haoyun's original numerical records, saturation and duration remain unavailable. Accordingly, **all-brine initial saturation (SCO2=0, Sbrine=1) is a new consistency-test assumption**, not a recovered historical condition. Production inference's seeded random CO2 saturation was not substituted. No existing optimization, later-step posterior forecast or high-rate no-control/BHP trajectory met the verified baseline conditions, so none was reused as zero-injection evidence.

The zero schedule and native zero target constructors accept exactly zero. However, active `InjectorControl` initializes a zero requested mass rate at 1e-12 kg/s and enforces a 1e-20 kg/s active-rate floor. This diagnostic explicitly uses `DisabledControl` to obtain exactly zero **surface** flow. Internal well/reservoir brine crossflow remains possible. The distinction is recorded; the near-zero production q₁,start/epsilon-zero audit remains deferred.

## Outcomes and definitions

| Window and scope | 3 MPa: pass/completed | 4 MPa: pass/completed | 5 MPa: pass/completed | Failed runs | Missing/unrun |
|---|---:|---:|---:|---:|---:|
| 0–480 days, primary pilot | 0/0 | 0/0 | 0/0 | 3 | 125 |
| 0–960 days, primary pilot | 0/0 | 0/0 | 0/0 | 3 | 125 |
| 0–8 days, separate default-solver diagnostic | 1/1 | 1/1 | 1/1 | 0 | Outside this one-member scope |
| 0–8 days, separate tighter-linear diagnostic | 1/1 | 1/1 | 1/1 | 0 | Outside this one-member scope |

The last two rows repeat **the same realization**, not two ensemble members. `0/0` means no evaluable completed trajectory, not a zero failure probability. Slurm array `13015513` timed out for all three positions. Logs show member 1 entered the ninth eight-day interval and member 128 entered the second; no complete 80-day block was written. In-memory progress was lost at termination and is not treated as saved pressure evidence. Member 64 has no completed report interval documented in its log. Timeout is not a fracture or pressure-limit failure.

The primary mask includes **all 131,072 reservoir cells**, matching production's unmasked objective. Uniform normalized cell-time weights retain padding; no pore-volume weighting is introduced. Secondary nonpadding and modified-padding metrics are exported. “Nonpadding” still includes top geometric boundary cells. Manuscript wording about the mask was not independently recovered. Initial time is checked separately and excluded from PoF denominators: a complete 480/960-day trajectory would contribute 60/120 saved times; the eight-day diagnostic contributes one.

For each member and Δ, comparisons use p>p0+Δ on the **same saved trajectory**. Thresholds never enter the simulator or trigger stopping. Relative margin r=(p0+Δ−p)/(p0+Δ) and loss max(0,−r) are recomputed for each Δ. Exact cell-time PoF, logistic surrogate with τ=0.05, and clean CVaR with α=0.01 are distinct outputs. CVaR retains production's fractional last tail weight, without an integer ceiling. Ensemble member failure fraction is a separate statistic. No bootstrap or optimization was performed.

The pressure comparison tolerance is **0 Pa**: CNV/MB and linear residual tolerances do not supply a justified pressure-error bound. Exact and adjusted flags are exported separately and coincide. Raw overpressure, margin and excess are in Pa and MPa; margin and excess are negatives of each other and are not independent insights. Missing results have blank metrics, not zeros.

At saved day 8, realization 741 had pressure extrema 101,325 and 16,000,000 Pa. Maximum overpressure occurred at all 512 top cells; the CSV reports the first location and tie count. All other cells had zero saved pressure change. Minimum margins were 2.961175, 3.961175 and 4.961175 MPa. Exact PoF and clean CVaR were zero for all limits and masks. Logistic surrogates were nonzero and were not classified as exceedances. Achieved surface mass rate and CO2 saturation were exactly zero.

## Numerical investigation and remaining uncertainty

The inherited top initial pressure is 62,500 Pa, below the reservoir pressure variable's 101,325 Pa minimum. Their difference exactly matches the observed top-row rise. Also, geometry uses cell centers while p0 uses iz×dz; initialization gravity and pressure-dependent brine density differ from the solver's discrete equilibrium. Initial vertical pressure drop minus average-density gravitational head ranges from **1,207.84 to 1,217.57 Pa per face**. This is a driving potential, not an error tolerance. These inconsistencies preclude calling the initial state an exact discrete hydrostatic equilibrium.

The default eight-day run (`13015764_1`) recorded 380 attempted internal steps: 127 accepted, 253 rejected, and 3,922 Newton updates. Accepted step lengths were 90–135 minutes. The limiting reported criterion was reservoir aqueous CNV. Production settings were retained: reservoir CNV 1e-3, MB 1e-7, well CNV 1e-2, MB 1e-3; CPR/BiCGStab linear relative tolerance 1e-3; maximum Newton iterations 15. The initial internal step was one day. The simulator invocation overrides the pre-simulation configuration snapshot's timestep-cut count with production's 1,000-cut limit.

A separately saved repeat (`13016431_1`) changed **only linear relative tolerance to 1e-6**, keeping nonlinear tolerances, initial conditions, controls and all thresholds identical. Pressure, surface rate, saturation and saved density extrema were bitwise identical, as were accepted/rejected-step and Newton counts. This checks that particular linear-tolerance sensitivity; it does not demonstrate convergence with respect to nonlinear tolerances or time refinement. No equilibrium initialization repair was substituted for the inherited setup.

Direct JLD2 reconstruction of nested solver-report tolerance dictionaries failed. Original files and failed export attempts were retained. A read-only HDF5 decoder uses raw iteration records and independently printed runtime tolerances; accepted intervals sum to eight days and counts match stdout. Valid exports are `short_diagnostic_8d/solver_steps_v4*.csv` and `tighter_linear_8d/solver_steps*.csv`. Pressure and restart arrays are independently readable. Numerical and serialization issues remain visible rather than being dropped.

## Resources, deliverables and next decision

The three primary jobs requested 4 CPUs and 24 GiB each for 45 minutes. Their observed peak RSS was at most approximately **2.53 GiB** before timeout. The completed default eight-day diagnostic used 479.492 CPU seconds and 500 elapsed seconds including startup; its block with raw reports occupies 54,046,459 bytes. The pilot, two short diagnostics and Slurm summary together consumed **2.481 CPU hours**, occupying **9.649 allocated core-hours**. The [accounting CSV](../../../data/diagnostics/zero_pressure_2026-09-09/execution_resources.csv) and [allocation assessment](../../../data/diagnostics/zero_pressure_2026-09-09/allocation_assessment.json) retain all jobs' measured costs.

For 128 members, uncompressed Float64 pressure plus p0 alone requires **7.625 GiB through 480 days or 15.125 GiB through 960 days**. Repeating the one-member eight-day benchmark mechanically gives about **1,023 / 2,046 CPU hours**, and about **387 / 773 GiB** of block files, respectively. These are conditional illustrations, **not reliable allocation estimates**: they repeat startup and restart overhead every eight days, later costs are unmeasured, and the other pilot members run much more slowly. A completed 80-day block's peak memory and report growth are also unknown. The failed pilot cannot support a defensible full-campaign upper bound.

The [bounded submission script](../../../scripts/shell/submit/submit_zero_injection_pressure.sh) supports all 128 positions with concurrency at most four, explicit wall-time limits and an approval gate. The [runner](../../../scripts/shell/run/run_zero_injection_pressure.sh) freezes source, locks each member, preserves attempts and resumes complete 80-day checkpoints. Currently none exists for the primary pilot. Do not use a short-diagnostic directory as a long-window restart. Any continuation should first agree a limited numerical investigation/pilot budget, then obtain approval for an evidence-based full allocation as required by task step 4.

The main deliverables are [per-member CSV](../../../data/diagnostics/zero_pressure_2026-09-09/summary_v3/per_member.csv), [aggregate CSV](../../../data/diagnostics/zero_pressure_2026-09-09/summary_v3/aggregate.csv), [initial checks](../../../data/diagnostics/zero_pressure_2026-09-09/summary_v3/initial_consistency.csv), [completed eight-day metrics](../../../data/diagnostics/zero_pressure_2026-09-09/short_diagnostic_8d/summary_v1/per_member_8day.csv), [short-window counts](../../../data/diagnostics/zero_pressure_2026-09-09/completed_short_window_counts.csv), [pressure-over-time PNG](../../../plots/diagnostics/zero_pressure_2026-09-09/short_diagnostic_8d/pressure_over_time_8day.png), [overpressure field PNG](../../../plots/diagnostics/zero_pressure_2026-09-09/short_diagnostic_8d/overpressure_field_8day.png), and [solver convergence PNG](../../../plots/diagnostics/zero_pressure_2026-09-09/short_diagnostic_8d/solver_convergence_8day.png). Long-window plots explicitly show unavailable results. Earlier summaries are preserved; `summary_v3` is current. Four analytical metric tests passed, shell syntax passed, scripts parsed, and the short simulations and report pipeline completed on Slurm. PNG layout was inspected.

## Wording limited to the completed implementation diagnostic

> A prospective eight-day numerical consistency check was conducted on one prespecified realization from the first-monitoring-step permeability ensemble, using an all-brine state and disabled surface injection. At the saved eight-day output, maximum pressure increase was 0.038825 MPa, equal to the correction between the inherited top-layer initial pressure and the simulator's pressure minimum. No saved cell exceeded its initial pressure plus 3, 4 or 5 MPa; a repeat with a tighter linear solver tolerance produced identical saved pressures. This short implementation diagnostic does not distinguish the candidate limits, establish 480- or 960-day behavior, or calibrate fracture resistance. The inherited initialization was not an exact discrete hydrostatic equilibrium, and the longer three-member pilot did not complete within its allocation.

No manuscript claim of a completed 480/960-day experiment is supported. New diagnostics cannot be the historical reason for choosing 4 MPa. No geomechanical calibration, optimization change or repair to the production PoF/CVaR definitions was made. A separate **post-hoc threshold sensitivity** analysis could evaluate unchanged saved injection trajectories, using prespecified member/window any-exceedance, exact cell-time PoF and clean CVaR as comparison criteria. That analysis has not been run; fresh matched optimizations require a separate scope and budget.
