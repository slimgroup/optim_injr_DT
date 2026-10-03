# BHP and ground-truth audit — 7 September 2026

This audit preserves the original simulations, plots, schedules and posterior exports. It distinguishes the selected base schedules from the sensitivity schedules actually used in several paper assets. No physically calibrated BHP limit has been identified in this synthetic model; a pressure trace must not be described as passing an operational BHP limit.

Diagnostic data directory: `data/diagnostics/bhp_audit_20260907_12902263/`. The inventory records hashes of the six original paper input files and all inspected simulator source files. Primary replay job: Slurm array **12902263**; additional Figure 1 replay: **12902563_6**. The initial diagnostic attempt, **12902241**, stopped because the wrapper does not retain `WellGroupConfiguration` in returned states; this exporter error was corrected without changing the simulator or original experiments. Its partial diagnostic files and logs were preserved.

## Verified facts and evidence

Paths below are relative to the repository unless they start with `$HOME`. The installed package roots are `$HOME/julia-depot/packages/Jutul/zUgxK`, `JutulDarcy/L8Awk`, and `JutulDarcyRules/2hBBA`.

| Question | Verified finding | Evidence / remaining gap |
|---|---|---|
| Code at replay audit | HEAD `d00940fe17a5c3f19a3aa402149613d1d7bc9ac9`; pre-existing uncommitted ECDF/statistics edits were preserved. | `input_inventory.json` records the working-tree status and source hashes. |
| Software | Julia 1.11.3; Jutul 0.2.11; JutulDarcy 0.2.7; JutulDarcyRules 0.2.8 in replay. | Runtime logs and `Manifest.toml:865–910`. Historical manifests attached to the inspected optimization finals specify the same three package versions/tree hashes. |
| Historical run identity | Representative sample-1 optimization finals record different commits by campaign, several with `-dirty`. | Exact paths, commits and historical manifest versions in inventory. The paper forward exports themselves contain **no run commit or dependency version manifest**; their original executed source state cannot be certified from their metadata alone. |
| Eight pressures | One accumulator/reference node plus seven perforated well nodes; one injector, not eight independent wells/BHPs. | Installed Darcy `src/types.jl:305–380`, `src/facility/wells/wells.jl:67–123`; replay geometry and CSV rows. |
| Canonical BHP | The first well pressure, at the first connected reservoir cell's center depth. | Darcy `src/facility/controls.jl:193–206`, `src/utils.jl:531–593`; numerical comparison against `well_output`. |
| Controls | Configured `InjectorControl(TotalRateTarget(q), [1,0], density=700)`; its default limit is the same rate, with no injector BHP limit. | Rules `src/FlowRules/Types/type_utils.jl:16–56`; Darcy `src/facility/types.jl:163–169,231`, runtime forces and achieved rates. |
| Optimization BHP constraint | `BHP_max` only feeds logged `BHP_max - node_pressure` arrays in the current PoF/CVaR objective. | `src/optim_inject.jl:438–569,690,843–845,982–984`; objective/feasibility depends on reservoir pressure risk, not BHP. |
| Physical BHP bound | Unresolved. Formation stress/fracture calibration, rated tubing/casing/packer data and annulus pressure are absent. | Repository model/setup and installed defaults described below. `p0+4 MPa` is the prescribed model fracture-pressure bound, evaluated on reservoir-cell pressures. |
| Selected versus plotted rates | Schedule figure: three base arrays. Risk-trajectory figure: base PoF ε=0, PoF ε=0.01 ×1.65, CVaR ×1.22. Figure 1 uses base PoF and CVaR ×1.22 at day 728. | `docs/reference/PAPER_FIGURE_MANIFEST.md`; `plot_injection_schedule_over_four_steps.py:31–125`; `plot_pressure_risk_trajectory_over_four_steps.py:22–24,75–87`. |
| No control | Actual plotted shutdown is day 728, during the tenth period of a 0→0.2 m³/s ramp over ten 80-day periods. | `no_control_delayed_ramp_10_periods.jld2`: `severe_substep=91`, `severe_day=728`, synthetic severe-margin threshold −0.1; schedule plot truncates injection there. |
| Local truth identity | `BroadK[2000,:,:]` is exactly equal to the dataset `K` in the same permeability file. All relevant forward generation scripts use this BroadK slice. | Numerical equality and hashes in inventory. |
| Optimization exclusion | Index 2000 is absent from all four current monitoring-step index arrays. | `data/state/new/Wise128_state_t{k}_rtm{k}_broad_NL_SNR28.jld2`, `idx_t{k}`. |
| Monitoring/CNF provenance | Abhinav's confirmation to Haoyun supports the statement that monitoring/digital-shadow validation and Figure 1 share permeability. | Original observation-generation code, truth-array identifier/hash and CNF training split/configuration are not present in the inspected repository. Direct cross-repository equality and complete training-exclusion verification remain open; this does not negate the coauthor confirmation. |

Representative `final.jld2` run stamps (sample 1; the full strings and file paths are in the inventory):

| Optimization campaign | Saved commit stamp |
|---|---|
| Step 1, PoF ε=0 / 0.01 | `3b89f2ed843bec2e9e15cb9794479ab417561bca` |
| Step 1, CVaR | `646687876cf0b7d28ac7bf47d60bf3a6a8c15b16-dirty` |
| Step 2, paired PoF ε=0 | `36d5c1bace04d4f5bafcddf0fb3c9ccbac55d347` |
| Step 2, paired PoF ε=0.01 / CVaR | `a481f5e293d9db2d660c8a19aca5d62fe9985a7b-dirty` |
| Step 3, all three paired cases | `1bf380f95e0be32acae5681ab9e98a9a32298b00` |
| Step 4, all three paired cases | `ec9c00c62e635604d2c08ce7ffd4cdd0c2d11369-dirty` |

These stamps identify inspected optimization examples, not a certified common commit for every ensemble member or forward figure. The `-dirty` suffix means the exact executed local edits are not recoverable from that commit alone.

## Well-pressure interpretation and physical-limit basis

The reservoir is a `(512,1,256)` grid of `(6.25,100,6.25)` m cells. For the current truth, the permeability maximum in `K[250,191:200]` selects grid z-index 192. The wrapper passes nominal coordinates `(1562.5,100,1200)` m and `endz=1237.5` m, which it converts to integer cell indices. The actual cell centers have x=1559.375 m and y=50 m. The reference depth is **1196.875 m**, not the deepest perforation and not the wellhead.

| Array entry | Physical role | Depth (m, positive down) | Connected reservoir index (x,y,z) |
|---|---|---:|---|
| 1 | Accumulator node; canonical reference-depth BHP | 1196.875 | No direct perforation |
| 2 | Well node, perforation 1 | 1196.875 | (250,1,192) |
| 3 | Well node, perforation 2 | 1203.125 | (250,1,193) |
| 4 | Well node, perforation 3 | 1209.375 | (250,1,194) |
| 5 | Well node, perforation 4 | 1215.625 | (250,1,195) |
| 6 | Well node, perforation 5 | 1221.875 | (250,1,196) |
| 7 | Well node, perforation 6 | 1228.125 | (250,1,197) |
| 8 | Well node, perforation 7 | 1234.375 | (250,1,198) |

The installed simulator solves well-node pressures with segment potential-drop/friction equations and Peaceman connections to reservoir cells. It exposes canonical BHP as `well_state.Pressure[1]`; `well_output(..., BottomHolePressureTarget)` returns that same quantity. Entries 1 and 2 share a depth but are distinct nodes, and their pressures need not be identical. Reservoir-cell pressures are separately exported at the connected cell indices; no pressure is mapped to a cell by guessing its hydrostatic depth. Earlier utilities `check_bhp_from_saved.jl` and `bhp_vs_pres_detail.jl` guess this mapping and incorrectly treat entry 1 as a perforation, so they are not used as evidence for this audit. Their injection/backflow labels also cannot be justified from a guessed raw pressure difference: the installed connection-flux calculation uses phase mobility and its configured density/gravity correction (`JutulDarcy/src/facility/cross_terms.jl:24–64`, `wells/wells.jl:223–250`). This audit reports pressures and locations, not inferred connection flow directions.

All simulator pressures are in **Pa**, exported here also as MPa. They use the simulator's absolute-pressure convention: default surface pressure 101325 Pa, PVT reference 150 bar, and a primary-variable minimum of 101325 Pa. There is no gauge-pressure subtraction in the pressure/BHP export. Physical datum calibration is nevertheless incomplete: initialization uses `rho_water * 10 * (iz*6.25+h)` without an atmospheric offset, uses cell-index depths rather than cell-center depths, and sets `h=0`; simulator gravitational potential uses 9.80665 m/s². These are inherited synthetic-model choices, preserved in the replay, not a validated conversion from an actual well gauge.

Default completion radius is 0.1 m and skin is zero. The multisegment constructor defaults to `SegmentWellBoreFrictionHB(L=1 m, roughness=1e-4 m, D_outer=0.1 m)` for every segment, including the accumulator connection. These default hydraulic parameters are not evidence of a rated tubing design or of a surface-to-reservoir tubing model. Reference phase densities are 700/1000 kg/m³, viscosities 1e-4/1e-3 Pa·s, and constant compressibilities 1e-4/1e-6 per bar. Surface reporting has a default 288.15 K; the injector-control object has a 273.15 K default. The chosen immiscible, nonthermal model does not simulate temperature evolution or establish a calibrated supercritical CO₂ temperature/pressure operating envelope.

No fracture test, minimum principal stress, geomechanical failure law, tensile strength, calibrated fracture gradient, rated casing/tubing wall/material, packer differential rating, annulus-pressure history, wellhead operating pressure or permit limit was found in the experiment model. The paper's `p_max[x,z] = p0[z] + 4 MPa` is the prescribed model fracture-pressure bound, evaluated on reservoir-cell pressures (`src/optim_inject.jl:635–638,697–700`). It retains its intended fracture interpretation as an existing synthetic-model assumption, although the 4 MPa margin is not independently physically calibrated. Counting cells above it represents exceedance of that prescribed fracture proxy, not a simulated fracture mechanics solution. Applying this proxy to specified well-side pressures would be an additional applicability assumption and is outside the completed audit.

For downward injection, conversion of a wellhead measurement to a specified bottom-hole reference would require `p_bh = p_wh + integral(rho*g*dz) - friction_loss`; equipment differential limits require the corresponding internal-minus-annulus pressure at each component. Formation limits at other depths likewise require consistent hydrostatic/friction corrections. The needed inputs are unavailable, so this audit neither replaces `BHP_max` with `max(p_max)` nor selects an arbitrary higher bound. This interpretation is consistent with [EPA guidance, §3.3, printed pp. 40–41](https://www.epa.gov/sites/default/files/2015-07/documents/epa816r13001.pdf); that guidance does not calibrate this synthetic experiment.

The current diagnostic expression `BHP_max = p_max[inj_y,250]` also reverses the `(x,z)` indexing of the `(512,256)` array. With the present model it evaluates to **19.625 MPa** (z-index 250), whereas the reservoir-cell threshold at `(250,192)` is 16 MPa. Neither is an established operational BHP bound. The bug affects logged differences only in the current PoF/CVaR path; it was not changed as part of this audit. `src/threshold_sensitivity.jl:439,833` uses the same diagnostic expression. In contrast, older archived scripts `optim_inject_cruyff.jl:184–189`, `optim_inject_cruyff_forward1.jl:179–184`, `optim_inject_forward1.jl:176–181`, `optim_inject_log_barrier.jl:317–322`, and `optim_inject_old.jl:317–322` do use a BHP barrier/feasibility test. They must not be conflated with the current selected PoF/CVaR campaigns.

Default pressure-update damping (20% relative Newton increment), a 1-atm pressure floor, and an effectively zero positive injector mass-rate floor are numerical safeguards. They do not provide an upper BHP constraint. The wrapper returns only `TotalSurfaceMassRate` in the saved facility state, so a historical operating-control-switch log cannot be reconstructed. Configured forces contain no BHP limit to trigger such a switch; replayed achieved rates provide a further numerical check. The optimization's `proj(x)=max.(x,0)` imposes nonnegative rates, not an upper pressure clamp.

## Numerical results

The audit replays the saved rate arrays without using the later ECDF-grid corrections or reoptimizing. It uses the original grid, permeability, fixed 0.5 ground-truth initial saturation blob, hydrostatic initial reservoir pressure, constitutive models and eight-day requested output intervals. It preserves the original simulator-call boundaries: ten outputs per rate period for base/PoF-sensitivity runs, and merged equal-rate segments for the CVaR video trajectory. As in the original wrapper, only reservoir state is carried between calls; the well state is initialized afresh by the wrapper. Replays run on Slurm with Julia/BLAS restricted to one thread within an eight-CPU allocation.

The full CVaR video and Figure 1 require separate replay variants. Direct comparison of their **original saved fields** at day 728 gives a maximum pressure difference of 1921.584 Pa and a maximum saturation difference of 0.0452719; the video has 93 threshold-exceeding cells, while Figure 1 has 97. The generation scripts differ in whether adjacent identical rates are merged into one simulator call, and the wrapper resets well state between calls. Thus equal permeability and equal piecewise-constant rates alone do not make these two numerical trajectories interchangeable. The extra Figure 1 replay uses its original ten-output period boundaries and one final output at day 728.

The old base exports save only 24 reservoir snapshots per controlled case, and the PoF ×1.65 export saves scalar pressure-risk diagnostics rather than fields. Full no-control/CVaR-video fields are available. None saves BHP. Therefore the audit exports new BHP at every requested eight-day output, compares all available old reservoir snapshots or scalar diagnostics, and separately checks the two relevant Figure 1 day-728 controlled fields. These are replays, not recovered historical well-pressure measurements. Internal adaptive solver ministeps and t=0 BHP are not included. Maximum pressure load and minimum relative margin obey `max(p/p_max)=1-min(r)` and are mathematically redundant; they are used for consistency checks, not treated as independent findings.

No-control coverage ends at day 728 (91 outputs). The underlying uncontrolled export actually simulated 800 days; the schedule figure/video implements shutdown after day 728. The trigger is the saved synthetic severe reservoir-margin criterion, not automatic BHP-limit switching. The old constant-0.1 no-control case in the base export is a different baseline and is not substituted for the current paper's delayed-ramp case. There is no post-shutdown BHP-compliance claim and no monitoring-step 3/4 no-control injection audit.

**All seven replays completed.** Coverage is ground truth only: five 1920-day runs and two 728-day runs, totaling 1382 requested output states and 11056 well-node records. There were no numerical solver failures in these completed replays.

| Case / actual source variant | Outputs | Final day | Maximum BHP (MPa) | Day of maximum |
|---|---:|---:|---:|---:|
| PoF ε=0 — base | 240 | 1920 | 14.554050 | 1848 |
| PoF ε=0.01 — base | 240 | 1920 | 15.012895 | 888 |
| CVaR α=0.01, γ=0.1 — base | 240 | 1920 | 16.148824 | 408 |
| No control — delayed ramp | 91 | 728 | 18.261640 | 728 |
| PoF ε=0.01 — ×1.65 risk figure | 240 | 1920 | 16.148188 | 408 |
| CVaR — ×1.22 risk/video figure | 240 | 1920 | 16.689953 | 408 |
| CVaR — ×1.22 Figure 1 variant | 91 | 728 | 16.689953 | 408 |

Per-monitoring-step maxima below are **MPa @ absolute day**, over eight-day outputs. Step 2 is partially covered for no control and the Figure 1 variant, ending at day 728.

| Case | Step 1 (0–480 d) | Step 2 (480–960 d) | Step 3 (960–1440 d) | Step 4 (1440–1920 d) |
|---|---|---|---|---|
| PoF ε=0 — base | 14.007427 @ 408 | 14.237556 @ 888 | 14.428331 @ 1368 | 14.554050 @ 1848 |
| PoF ε=0.01 — base | 14.978166 @ 408 | 15.012895 @ 888 | 14.892171 @ 968 | 14.771262 @ 1448 |
| CVaR — base | 16.148824 @ 408 | 15.995559 @ 888 | 15.864486 @ 968 | 15.590224 @ 1448 |
| No control | 17.300623 @ 408 | 18.261640 @ 728 | N/A — after shutdown | N/A — after shutdown |
| PoF ε=0.01 — ×1.65 | 16.148188 @ 408 | 16.140007 @ 888 | 16.001351 @ 968 | 15.877487 @ 1448 |
| CVaR — ×1.22 risk/video | 16.689953 @ 408 | 16.548267 @ 888 | 16.411345 @ 968 | 16.082527 @ 1448 |
| CVaR — ×1.22 Figure 1 | 16.689953 @ 408 | 16.355786 @ 728 | N/A — no replay | N/A — no replay |

**Physical BHP compliance remains unresolved for every case.** Minimum margin, exceedance count and exceedance duration against a physical BHP limit are blank/NaN in the summary CSV because no calibrated bound exists; those blanks do not mean zero exceedances. The plotted curves carry no arbitrary limit line. Passing on this truth would in any event not establish ensemble-wide safety.

**Replay validation.** Canonical `well_output` BHP and node 1 agree exactly at all 1382 outputs. Maximum achieved-versus-requested rate error is 1.11×10⁻¹⁶ m³/s. Against the corresponding saved field exports, maximum reservoir-pressure discrepancy is 89.501 Pa (0.000089501 MPa), and maximum saturation discrepancy is 4.24×10⁻⁵ including the separate PoF Figure 1 comparison. These are close numerical reproductions, not bitwise-identical historical reconstructions; the pressure differences do not directly bound error in historical BHP, which was not saved.

The PoF ×1.65 export lacks full fields: all 240 saved scalar load/count diagnostics were checked instead, with maximum load difference 2.27×10⁻⁷ and identical cell counts. At day 896, the CVaR video replay's count of 1912 agrees with the original saved integer diagnostic (1912), while recomputing the count from the original **Float32 pressure-field export** gives 1911. Thus export rounding changes one near-threshold cell's classification; maximum replay-versus-export pressure difference at that time is 0.6997 Pa. The one mismatch recorded in `validation_summary.json` refers to this count recomputed from the saved field, not to the original integer diagnostic; `metadata_count_validation.json` separately checks the integer diagnostics. Other available same-variant saved field counts match. The dedicated Figure 1 CVaR replay matches its 97 cells at day 728, with maximum pressure discrepancy 0.266224 Pa and saturation discrepancy 2.87×10⁻⁶; the full-video comparison to Figure 1 is explicitly a different-variant comparison.

**Reservoir-cell threshold outcomes, distinct from BHP compliance.** Neither base PoF case exceeds `p0+4 MPa` in its 240 replay outputs. Base CVaR first exceeds it at day 408, with at most 9 cells above threshold. PoF ×1.65 first exceeds it at day 408, with at most 8 cells; CVaR ×1.22 first exceeds it at day 328, with at most 2285 cells. No control first exceeds the cell threshold at day 248 and has 6953 exceeding cells at the day-728 shutdown. These do not constitute failures of an unspecified BHP limit, and a nonzero cell count does not by itself prove failure of a PoF/CVaR constraint that allows nonzero tail risk.

Artifacts under the diagnostic directory: `bhp_summary.csv` contains all-case and per-step extrema; `bhp_timeseries.csv` contains reference-depth BHP and achieved rates; `*_pressures.csv` contain each node/perforation and connected-cell pressure/depth in Pa; `well_geometry.csv` supplies the mapping; `*_validation.csv` and `validation_summary.json` retain numerical discrepancies. The reviewed figure is `plots/paper_figures/bhp_audit_20260907_12902263_final/bhp_selected_schedules.png`. The earlier plotting draft is retained separately. The user requested deletion of this reviewed figure's PDF on 7 September 2026; subsequent BHP plots default to PNG only. For the four original strategies alone, use `plots/paper_figures/bhp_four_selected_strategies_20260907/bhp_four_strategies.png` and the accompanying `BHP_FOUR_STRATEGIES_PAPER_NOTE_2026-09-07.md`.

Reproduce with `sbatch scripts/shell/submit/submit_paper_bhp_audit.sh` (seven array tasks, a new job-specific diagnostic directory), then run `summarize_bhp_audit.py DATA_DIR NEW_PLOT_DIR` in the plotting Python environment. Both scripts reject existing output targets.

## Permeability provenance and exclusion

Dataset: `data/geo/wise_perm_models_2000_new.jld2`, `BroadK`, Julia shape `(2000,512,256)` and truth slice `(512,256)` in `(x,z)` order. HDF5/h5py sees `(256,512,2000)` and slice `[:,:,1999]` in `(z,x)` order. Values are Float32 mD; simulation multiplies by `9.86923266716013e-16` to obtain m² and uses vertical/horizontal permeability ratio 0.36. The truth equals the same file's standalone `K` array element-for-element, with maximum difference **0 mD**.

SHA-256 of the Float32 little-endian truth slice, serialized in Julia `(x,z)` column-major order (equivalently h5py `(z,x)` C order):

`fb6b891d72e6dad08ed1338908fb736922913dbfdc09d9b33df64584724c2246`

The same hash is independently recorded by the Julia replays. Relevant forward assets save `ground_truth_idx=2000`, and their generator scripts point to this same dataset/path. The replay-to-saved-field comparisons provide stronger corroboration than equal indices alone. The permeability figure also explicitly reads slice 1999 with h5py. None of these forward exports embeds its original permeability hash, so a historical file replacement cannot be ruled out from the old metadata alone.

| Current optimization index file | Entries | Unique indices | Index range | Count equal to 2000 |
|---|---:|---:|---|---:|
| t1 / rtm1 | 128 | 125 | 16–1976 | 0 |
| t2 / rtm2 | 128 | 128 | 16–1956 | 0 |
| t3 / rtm3 | 128 | 128 | 5–1977 | 0 |
| t4 / rtm4 | 128 | 128 | 42–1991 | 0 |

The two available old index arrays also exclude 2000. The repeated indices at t1 are recorded here rather than silently treating the 128 entries as 128 distinct permeability realizations. A numerical duplicate check over all 2000 BroadK fields also found that **only index 2000 equals the truth**: a discriminating entry `(x=250,z=192)` was compared for all realizations, then all entries of every remaining candidate were compared. Thus the checked optimization/forecast ensembles exclude the actual truth field, not merely its index. This does not independently prove the CNF's final training/validation split or exclusion of the truth from every original state-observation training pair; posterior exports contain `X_post1/2/3` and `pres_Hyd`, without truth permeability or a training-split manifest. The original observation-generation code and data identifier are needed to complete that chain.

Abhinav's reported confirmation that Figure 1 and digital-shadow validation use the same truth remains the coauthor evidence for their shared permeability. Shared permeability does not mean shared state history: base, sensitivity and no-control schedules produce different saturation/pressure trajectories, and the ground-truth forward scripts use a fixed 0.5 saturation blob, while first-step optimization initialization has its own seeded randomized state.

The published [Gahlot et al. (2025), §§4.1–4.2](https://academic.oup.com/gji/article/242/1/ggaf176/8142541) describes a Compass-derived synthetic test with a 0.05 m³/s injection schedule and randomized initial saturation. This is a distinct experiment. Its use of Compass, similar dimensions or a reported injection depth does not establish equality with the current truth array. No such cross-paper numerical equality is claimed.

## Manuscript wording supported by this audit

The injector is represented by an eight-node multisegment well, with the simulator BHP defined at a reference depth of 1196.875 m and seven connections to reservoir cells. At eight-day saved outputs, ground-truth replays of the historical selected PoF (ε=0 and 0.01) and CVaR (α=0.01, γ=0.1) schedules yielded maximum BHPs of 14.554, 15.013 and 16.149 MPa, respectively, over 1920 days, while the no-control ramp reached 18.262 MPa at its day-728 shutdown. The prescribed model fracture-pressure bound p_max=p0+4 MPa is evaluated on reservoir-cell pressures; the BHP trajectories are reported as a posteriori diagnostics because an independently calibrated BHP operating limit is not specified.

For the concise paragraph and single-panel PNG intended for transfer to the paper repository, see `docs/historical/analysis/BHP_PAPER_REPO_HANDOFF_2026-09-07.md`.

The paper caption should continue to identify the Figure 1 CVaR fields as a 22% increase over the base schedule. The current Figure 1 annotation displays base-schedule rate/mass, while the actual fields come from the multiplied schedule, as already documented in `PAPER_FIGURE_MANIFEST.md`. Likewise, the pressure-risk trajectories and the base-schedule figure should not be described as the same forward experiment.
