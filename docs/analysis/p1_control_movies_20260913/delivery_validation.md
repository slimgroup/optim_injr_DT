# Three selected controlled campaigns — delivery and validation

Prepared 2026-09-13 for DTControl proposal page 39. Rendering job: **13166581**, completed on Slurm in 4 min 46 s. No training, optimization, or forward simulation was launched for this delivery. All earlier data, figures, movies and partial rendering outputs remain intact.

**Delivery status:** four synchronized, 40-second movies are complete using **79 common saved spatial states**. A complete eight-day spatial trajectory is unavailable for strict PoF and base CVaR after day 480; this is an explicitly labelled existing-data edition. The manuscript's three rounded masses agree with the selected base schedules, but two quoted peak cell counts belong to sensitivity variants. Do not present those counts as results of these base movies.

## Files and slide use

| Policy/export | MP4 | PNG poster (day 1920) | PNG day-728 still | Dimensions |
|---|---|---|---|---|
| Combined, in requested order | [comparison.mp4](../../../plots/paper_figures/p1_control_movies_20260913_13166581/comparison.mp4) | [poster](../../../plots/paper_figures/p1_control_movies_20260913_13166581/comparison_poster.png) | [day 728](../../../plots/paper_figures/p1_control_movies_20260913_13166581/comparison_day728.png) | 3840 × 2160 |
| PoF ε=0 | [pof_eps0.mp4](../../../plots/paper_figures/p1_control_movies_20260913_13166581/pof_eps0.mp4) | [poster](../../../plots/paper_figures/p1_control_movies_20260913_13166581/pof_eps0_poster.png) | [day 728](../../../plots/paper_figures/p1_control_movies_20260913_13166581/pof_eps0_day728.png) | 1280 × 2160 |
| PoF ε=0.01 | [pof_eps001.mp4](../../../plots/paper_figures/p1_control_movies_20260913_13166581/pof_eps001.mp4) | [poster](../../../plots/paper_figures/p1_control_movies_20260913_13166581/pof_eps001_poster.png) | [day 728](../../../plots/paper_figures/p1_control_movies_20260913_13166581/pof_eps001_day728.png) | 1280 × 2160 |
| CVaR α=0.01, γ=0.1 | [cvar_alpha001_gamma01.mp4](../../../plots/paper_figures/p1_control_movies_20260913_13166581/cvar_alpha001_gamma01.mp4) | [poster](../../../plots/paper_figures/p1_control_movies_20260913_13166581/cvar_alpha001_gamma01_poster.png) | [day 728](../../../plots/paper_figures/p1_control_movies_20260913_13166581/cvar_alpha001_gamma01_day728.png) | 1280 × 2160 |

All MP4s use H.264, yuv420p, 30 fps, exactly 1200 encoded frames / 40 seconds, no audio, and fast-start metadata. Prefer the combined movie for one full-slide playback object. If individual slots are required, start all three together once and use the same playback settings; do not independently loop them. No slide or paper repository was modified.

The combined and individual exports preserve axes, legends, annotations and identical saved-state timing. `playback_timeline.json` gives the start frame and repetition count of every saved day. The clock denotes the actual field being shown, remaining fixed during frame repetitions. Screen durations are proportional to physical gaps, quantized to 1/30 second. With no saved t=0 field, day 8 is shown from the beginning; the final day-1920 image receives a short final hold. No spatial or temporal field interpolation is used.

## Source / validation table

All data filenames below are relative to the original `plots/paper_figures/` directory. These files were read without modification. Source hashes and sizes are in `validation.json`; exported schedules are in `historical_implemented_rates.csv`.

| Case | Historical forward run IDs from retained logs | Implemented schedule source | Saved-time range and count | Spatial data files | Grid / units | Shared color limits | Result checks |
|---|---|---|---|---|---|---|---|
| PoF ε=0 | Base **9523888**; first interval **9537372_0**; day 728 **9798781_0** | A: `POF_eps0_rates`, 24 implemented 80-day periods; B and D rates agree | 8–1920 days; **79** states; 161 eight-day outputs absent | A + B + D | G below: 512×1×256; pressure Pa; time days; rates m³/s | r [−1,1]; Δp [−0.1,4.1] MPa; S [0,1] | 4.931200512 Mt; peak available count 0; strict day-728 reference is same source |
| PoF ε=0.01 | Full saved ground-truth trajectory **9820154_0**; schedule A from **9523888** | F: `rate_by_substep` equals each of A's `POF_eps0p01_rates` repeated 10 times | 8–1920 days; **240** states, 79 used in synchronized movies | F (A for schedule consistency) | G; F pressure/saturation stored Float32 | Same limits | 6.947603712 Mt; peak available count 0, **not 8** |
| CVaR α=0.01, γ=0.1 | Base **9523888**; first interval **9537372_1**; day 728 **9798781_1** | A: `CVaR_g01_a001_rates`, 24 implemented 80-day periods; C and E rates agree | 8–1920 days; **79** states; 161 eight-day outputs absent | A + C + E | G; A–E pressure/saturation stored Float64 | Same limits | 10.706701824 Mt; peak available count 9, **not 2285**; reference CVaR uses ×1.22 fields |

- **A** `forward_sim_four_steps_base_data.jld2`.
- **B** `first_step_substeps_POF_eps0.jld2`.
- **C** `first_step_substeps_CVaR_g01_a001.jld2`.
- **D** `controlled_day728_POF_eps0.jld2`.
- **E** `controlled_day728_CVaR_g01_a001.jld2`.
- **F** `full_campaign_video_POF_eps001.jld2`.

Relevant original generators, all under `scripts/julia_scripts/data_collection/forward_exports/`: `run_forward_four_steps_base_export.jl`, `run_first_step_reference_substeps.jl`, `run_controlled_day728_from_day720.jl`, and `run_full_campaign_video_cases.jl`. The historical schedules were copied into the base generator from the documentation at the time of that run; **the saved arrays, not today's edited `docs/injection_rate_arrays.md`, are authoritative for these movies**. Their six implemented periods per monitoring interval are used; the unused remaining MPC look-ahead entries are not appended. No ECDF recalculation, rate scaling or constant-rate substitution was performed.

Run IDs are supported by the retained `out_fwd_four_steps_base_9523888.txt`, `out_real_frac_ref_9537372_{0,1}.txt`, `out_ctrl_day728_9798781_{0,1}.txt`, and `out_video_forwards_9820154_0.txt` logs under `logs/`. The old exports do not embed their executed git commit or dependency manifest, so these log/source associations do not certify an exact historical source checkout. Current source hashes are supplied separately, without claiming they are historical execution hashes.

## Common physical configuration (G)

- **Truth:** Julia slice `BroadK[2000,:,:]` in `data/geo/wise_perm_models_2000_new.jld2`; h5py reads `BroadK[:,:,1999]`, shape `(256,512)` in `(z,x)` order. Every movie input saves `ground_truth_idx=2000`. The read-only slice SHA-256 is `fb6b891d72e6dad08ed1338908fb736922913dbfdc09d9b33df64584724c2246`. Original generators use this same path/index. Permeability converts mD to m² using 9.86923266716013e−16; vertical/horizontal ratio is 0.36. The existing September 7 BHP audit verifies equality with the file's standalone `K` and exclusion from the four inspected optimization index arrays. Original exports lack a permeability hash, so historical file replacement and complete training-split provenance cannot be independently excluded.
- **Grid and initial state:** `(512,1,256)` cells, `(6.25,100,6.25)` m spacing, top depth `h=0`. All three generators use the same fixed 0.5 CO₂ saturation blob around the injector, zero elsewhere, and hydrostatic initialization from `jutulSimpleState`. Although they call `Random.seed!(2025)`, the blob is assigned deterministically. This saved ground-truth campaign initialization differs from the randomized initialization of first-step optimization; no posterior state was substituted.
- **Porosity/boundary:** interior porosity 0.25. The inherited `jutulModel(..., pad=true)` default sets the first/last x columns and bottom z layer to 1e8 effective porosity (pore-volume padding); the top is 0.25 at h=0, including top corners. The Cartesian exterior has no explicitly imposed flux/pressure boundary in these calls. Preserve this padded model; it is not a new open-boundary prescription. Source: installed `JutulDarcyRules/2hBBA/src/FlowRules/Types/jutulModel.jl:11–20`.
- **Pressure:** raw reservoir pressure is Pa using the simulator's absolute-pressure convention; no gauge subtraction is applied before computing the requested fields. The inherited synthetic reference uses `p0(iz)=iz×6.25×1000×10 Pa`, no atmospheric offset and index rather than cell-center depths; simulator gravity is 9.80665 m/s². These inherited choices were not recalibrated. All p0 arrays match exactly, and all saved pmax arrays equal p0+4,000,000 Pa exactly.
- **Orientation and well:** plots display `(z,x)` fields, depth increasing down, all original cells retained. Extent matches the spatial reference: x=0…3193.75 m, z=0…1593.75 m. Nominal well annotation x=1562.5 m, z=1200…1237.5 m; the simulator maps to cells `(250,1,192:198)`. Actual cell-center x=1559.375 m and completion depths=1196.875…1234.375 m. The plot keeps the reference's nominal-coordinate convention; it does not silently transpose or vertically flip the fields.
- **Mass and rate:** cumulative injected mass is `700×86400×sum(q_i×elapsed_days_i)/1e9` Mt. Density 700 kg/m³ is the model's injection control reference density. Mass excludes the initial saturation blob. Rate display uses the historical end-of-output convention: the rate on `(t_previous,t]` that produced the saved state, including at an 80-day change or 480-day monitoring boundary. It is displayed to five decimal places; the saved numerical inputs remain unchanged. Monitoring step is `ceil(day/480)`.

## Time and state continuity

The common saved days are **8,16,…,480; 560,640,720,728,800,880,960,1040,…,1920** (79 total). The full lists and 161 missing eight-day times for each sparse case are in `validation.json`. File lengths were audited rather than assumed: A has 24 snapshots with saved indices 10,20,…,240 and period_days=80; B/C have 60 states and dt_days=8; D/E explicitly save day=728; F has 240 states and dt_days=8. No file supplies a saved day-0 field.

For strict PoF/CVaR, all 12 overlaps between A and B/C at days 80…480 are exactly equal for pressure and saturation and were deduplicated. The original base generator carries the preceding reservoir state through all 24 implemented periods, including monitoring boundaries; no posterior update resets this forward truth. D/E were produced by continuing the saved day-720 reservoir state for eight days under period 10's rate. They are historical saved continuations, not unused forecasts. PoF ε=0.01 uses F's single complete saved trajectory consistently, without splicing in A's snapshots. Its generator merges adjacent equal-rate segments. The legacy wrapper reinitializes well state between calls while retaining reservoir state; these different call boundaries can produce small differences between historical exports with equal schedules. No new mixing of numerical trajectories was introduced.

The existing BHP audit at `docs/analysis/BHP_GROUND_TRUTH_AUDIT_2026-09-07.md` and `data/diagnostics/bhp_audit_20260907_12902263/` includes eight-day **diagnostic replays**, but does not save the missing spatial fields. Those CSVs cannot supply pressure/saturation maps. They independently report full-replay base peak counts 0,0,9; these are corroborating replay results, not recovered historical fields or evidence of unsaved extrema between outputs.

## Field and reference checks

| Check | Observed | Interpretation |
|---|---|---|
| Day-1920 masses, requested order | 4.931200512; 6.947603712; 10.706701824 Mt | Round to requested 4.93; 6.95; 10.71 |
| Peak exceeding-cell counts over all available spatial fields | 0; 0; 9 | PoF ε=0.01 and CVaR disagree with manuscript 8; 2285 |
| Sources of 8 and 2285 | `pof_eps001_full_campaign_sensitivity_1p65x.jld2`; `full_campaign_video_CVaR_g01_a001_sensitivity.jld2` | Sensitivity diagnostics, not base fields; excluded from the three selected movies |
| Day 728: strict PoF | min r=0.1193159845; count 0; mass 0.837019008 Mt; q=0.03745 | Same saved field as strict PoF column of the spatial reference |
| Day 728: PoF ε=0.01 | min r=0.0767787317; count 0; mass 1.4274392832 Mt; q=0.06203 | Actual controlled run; no column in the original 3×3 reference |
| Day 728: base CVaR | min r=0.02413016945; count 0; mass 2.3358150144 Mt; q=0.09906 | Correct selected base run |
| Day-728 CVaR reference discrepancy | Reference source `cvar_day728_sensitivity_1p22x.jld2` has 97 cells; max absolute pressure difference=0.4494512114 MPa and saturation difference=0.7306079065 | Reference image uses ×1.22 fields despite base rate/mass annotations; documented previously in `docs/reference/PAPER_FIGURE_MANIFEST.md` |
| Separate no-control shutdown | Day 728; 3.967488 Mt; 6953 exceeding cells; min r=−0.1072997468 | Matches rounded 3.97 Mt. Excluded. Underlying delayed-ramp file saves through day 800, but selected shutdown/reference ends at 728; no extension or substitution here |

The separate check used `no_control_delayed_ramp_10_periods.jld2`, not the unrelated constant-0.1 baseline in A. The old `fracture_comparison_three_cases_full_campaign.mp4` also has a different case selection (including sensitivity/no control) and was not reused.

Fields are computed from raw reservoir pressure: `r=(pmax−p_res)/pmax`, `Δp=(p_res−p0)/1e6 MPa`, and original CO₂ saturation. Full available-field extrema are r=[−0.0005139670602,0.9750584615], Δp=[−0.006152097844,4.00793436649] MPa, S=[0,0.8979757213]. Shared limits encompass every value without clipping. Margin uses a symmetric diverging scale centered at zero; a separately labelled red overlay marks every negative-margin cell, making small exceedances visible. The negative values are retained in diagnostics and scaling. No panel crops, per-frame normalization, pressure-limit recalibration or field smoothing are applied. PoF ε=0.01 counts are computed from its available Float32 export, retaining that source precision.

A count at one saved time is instantaneous spatial occupancy above the prescribed pressure limit. It is neither proven fracture/leakage nor an ensemble/space-time PoF. `max(p/pmax)=1−min(r)` is mathematically redundant with the shown minimum margin, so it is not presented as an additional insight.

## Concise captions

**Combined:** “Physical-time evolution of three controlled ground-truth campaigns: PoF ε=0, PoF ε=0.01, and CVaR α=0.01, γ=0.1. Rows show relative safety margin, pressure increase and CO₂ saturation under each historical implemented schedule. Red cells indicate pressure-limit exceedance. Shared saved times and color scales; outputs are every 8 days to day 480, then every 80 days plus day 728.”

**Individual:** “Ground-truth evolution under [policy], synchronized with the other two selected policies. Relative safety margin, pressure increase and CO₂ saturation use shared scales; annotations report the rate that produced the saved state, cumulative injected mass, minimum margin and instantaneous exceeding-cell count. Later spatial outputs are sparse.”

**Day-728 still:** “Three selected controlled campaigns at day 728 (monitoring step 2). The CVaR field is the unscaled historical run; the earlier spatial reference used a ×1.22 sensitivity run in that column.”

## Validation and reproducibility

`validation.json` records input hashes, rates/time/grid checks, deduplications, all missing times, shared extrema and the day-728 quantitative comparison. `saved_time_validation.csv` contains one row per available case/time (398 rows) with source file, dataset names and zero-based array index. `media_validation.json` verifies all container formats, dimensions, durations and 1200 encoded frame counts. The full-decoder check `decode_validation.json` (Slurm **13167898**) passed all 1200 frames in each of the four movies with no decoder errors. The preliminary check job 13167820 could not access a login-node /tmp script; its log is retained and the successful check used shared storage. `output_checksums.json` records all four movies and eight still-image hashes. First-state, day-728 and final layouts were visually inspected for clipping, orientation, colorbar alignment and legibility.

Reusable renderer: `scripts/python_plots/create_selected_control_movies.py`; media validator: `scripts/python_tools/analysis/validate_selected_control_media.py`; Slurm wrapper: `scripts/shell/submit/submit_selected_control_movies.sh`. It refuses an existing output directory and only reads simulation inputs. Rendering runs on allocated compute nodes (4 CPUs, 12 GB, 90-minute limit; completed in under five minutes). The wrapper runs no Julia. If reproducing, run the wrapper from the repository root; it creates a new job-specific export directory.

## Optional complete eight-day version — approval required before simulation

Missing: strict PoF and unscaled CVaR pressure/saturation maps at 161 eight-day outputs each after day 480. Searching the existing exports and diagnostic directories did not recover them. This edition uses only existing fields; it does not imply complete eight-day coverage.

Proposed budget: **two Slurm forward-only replay jobs, each 8 CPUs, 16 GB RAM, 90 minutes maximum** (24 allocated CPU-hours maximum; estimated 20–40 minutes each excluding queue wait). Resume from each exact saved day-480 reservoir state and preserve the original 18 remaining 80-day simulator calls and historical rates. Save all 180 eight-day states per case to new files, including the 19 later fields already available for validation. Compare the 18 period endpoints and day 728 before combining. The two Float64 pressure+saturation exports require about 0.70 GiB raw, so reserve 1 GiB plus rendering space. No training or optimization is needed. Historical timings (roughly 9 minutes for 480 days and 27 minutes for a full saved-video trajectory in 8-CPU allocations) inform this estimate; wall time is not guaranteed.

A replay would create new numerical fields, not recover the missing historical files; numerical discrepancies and original-call-boundary compatibility must be reported. The original forward exports lack an executed dependency manifest. A saved t=0 image would also need a separately labelled reconstruction of the documented initial state. **No such replay/reconstruction has been launched.** Approval is required by this request's explicit ban on new forward runs without a budget decision.
