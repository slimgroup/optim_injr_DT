# BHP results for the four selected strategies

This paper-facing subset contains only the original selected PoF ε=0, PoF ε=0.01 and CVaR α=0.01, γ=0.1 schedules, and the delayed-ramp no-control case. All four replays use `BroadK[2000,:,:]` from `data/geo/wise_perm_models_2000_new.jld2`, the same initial ground-truth state, grid and model parameters. No schedules were reoptimized. Historical rates were retained. No sensitivity-multiplied schedules are included in this subset.

| Strategy | Maximum reference-depth BHP (MPa) | Time of maximum (days) | Checked through day |
|---|---:|---:|---:|
| PoF ε=0 | 14.554 | 1848 | 1920 |
| PoF ε=0.01 | 15.013 | 888 | 1920 |
| CVaR α=0.01, γ=0.1 | 16.149 | 408 | 1920 |
| No control | 18.262 | 728 | 728 |

## What the eight entries mean

At each requested output time, `state[:Injector][:Pressure]` is a length-8 vector in Pa. It contains one accumulator/reference node and seven perforated well nodes. The simulator defines canonical BHP as entry **1**, at reference depth **1196.875 m**. The table reports `max_t(well_pressure[t][1])`, not the maximum or average of all eight node pressures. The numbers use the simulator's absolute-pressure convention.

Each controlled case has 240 requested eight-day outputs, each with eight node pressures. No control has 91 outputs through day 728, each with eight node pressures. Adaptive internal solver ministeps and t=0 BHP are not covered by these maxima.

## Which BHP limit to use

No physically calibrated numerical BHP limit can be selected from the present experiment inputs. The recommended treatment for this manuscript is to report BHP as an **a posteriori ground-truth diagnostic**, with no unsupported pass/fail statement.

A defensible operational bound requires formation fracture/stress information and well-component pressure or differential-pressure ratings, with the applicable pressures converted to the same reference depth and pressure convention. That conversion requires hydrostatic/friction information and, for differential ratings, the relevant annulus pressure. See [EPA (2013), §3.3](https://www.epa.gov/sites/default/files/2015-07/documents/epa816r13001.pdf). This source explains the physical distinctions; it does not supply a numerical limit for this synthetic model.

The prescribed model fracture-pressure bound `p_max[x,z]=p0[z]+4 MPa` is an existing synthetic-experiment assumption, evaluated on reservoir-cell pressures. Its fracture interpretation is explicit in `src/optim_inject.jl:635–638,697–700`; lack of physical calibration does not remove that interpretation. It is not an independently calibrated BHP bound. Nor is the old diagnostic `BHP_max=19.625 MPa`: its expression reverses the array indices, and it does not constrain the current optimization. Choosing a cap after inspecting the maxima would not establish physical safety. Extending the model fracture-pressure bound to specified well-side pressures would require a separate assumption about applicability and matching pressure/depth conventions. No such additional screening was performed here.

## What the replay differences mean

The previously reported 89.5 Pa is the maximum cellwise reservoir-pressure difference between the new replays and available corresponding historical reservoir snapshots. It equals 0.0000895 MPa. It measures replay agreement; it is not a BHP-limit exceedance, not a calibrated BHP error bar, and not the amount by which BHP differs from reservoir pressure.

The 0.266 Pa / 97-cell result belongs to the separate ×1.22 CVaR Figure 1 audit. It is outside this four-strategy subset and need not be included in this subsection of the paper.

“Ground truth only” means these four schedules were evaluated on one fixed permeability realization. The BHP histories were not evaluated across all optimization-ensemble permeability realizations. Thus the table is valid for the ground-truth experiment; it does not establish an ensemble-wide probability of BHP-limit compliance.

## Suggested manuscript text

To complement the reservoir-pressure fracture-risk assessment, we evaluated the bottom-hole pressure (BHP) response of the selected injection schedules on the ground-truth permeability realization. BHP was extracted at the injector reference depth of 1196.875 m using the simulator's absolute-pressure convention. At eight-day saved outputs, the maximum BHPs over 1920 days were 14.554, 15.013 and 16.149 MPa for PoF (ε=0), PoF (ε=0.01) and CVaR (α=0.01, γ=0.1), respectively; the no-control case reached 18.262 MPa at its day-728 shutdown. The prescribed model fracture-pressure bound, p_max(x,z)=p0(x,z)+4 MPa, is evaluated on reservoir-cell pressures. These BHP results are reported as a posteriori diagnostics because an independently calibrated BHP operating limit is not specified in the synthetic model.

Ready-to-transfer manuscript paragraph, figure caption and integration instructions: `docs/analysis/BHP_PAPER_REPO_HANDOFF_2026-09-07.md`.

## Artifacts

- CSV summary, reference-depth time series, all eight well-node pressures and a LaTeX table: `data/diagnostics/bhp_four_selected_strategies_20260907/`.
- Paper figure (PNG): `plots/paper_figures/bhp_four_selected_strategies_20260907/bhp_four_strategies.png`.
- Reusable exporter: `scripts/python_plots/plot_bhp_four_selected_strategies.py`.
- Full provenance and numerical verification: `docs/analysis/BHP_GROUND_TRUTH_AUDIT_2026-09-07.md` and `data/diagnostics/bhp_audit_20260907_12902263/`.

The figure marks each curve's maximum with a dot. Dotted vertical lines indicate monitoring-step boundaries; the no-control trace ends at shutdown. No assumed BHP limit is drawn.

This single-panel figure is the appropriate subset for reporting the four original strategies. The older two-panel `bhp_audit_20260907_12902263_final/bhp_selected_schedules.png` also includes the multiplied sensitivity schedules in its right panel; those curves are different forward experiments. Its left panel contains the same original four histories as the single-panel subset.

On 7 September 2026, the user requested PNG-only output by default. Both BHP plotting scripts now require an explicit `--pdf` flag to export PDF. The user specifically authorized removal of `plots/paper_figures/bhp_audit_20260907_12902263_final/bhp_selected_schedules.pdf`; the corresponding PNG and other existing artifacts are preserved.
