# Continued-injection no-control comparison — 2026-09-14

The user requested that no control continue beyond the previously displayed day-728 endpoint, to assess the pressure-limit violation if injection is not stopped. This explicitly authorizes one new forward continuation. The policy selection remains **PoF ε=0.0; CVaR α=0.01, γ=0.1 using the existing 1.22× sensitivity trajectory; no control with continued injection**. No training or optimization is rerun.

This is a counterfactual under the existing flow model. It measures pressure-limit exceedance, not fracture opening or leakage. Continuing injection does not imply that the exceeding-cell count or pressure excess must increase monotonically.

## Computed no-control result

The continuation completed successfully in **11 min 26 s**, using a recorded maximum resident memory of **5,270,144 KiB**, within the announced budget. All 240 eight-day outputs are present, with no duplicate or missing times. All 100 historical pressure/saturation states are preserved exactly. The achieved injection rate equals 0.2 m³/s at all 140 new output times (maximum absolute error 0 in the exported diagnostics).

| Saved day | Cumulative injected CO₂ [Mt] | Exceeding cells | Minimum r | Maximum pressure excess [MPa] |
|---:|---:|---:|---:|---:|
| 728 | 3.967488 | 6953 | −0.1072997467733469 | 1.6497336066402084 |
| 800, restart state | 4.838400 | 6566 | −0.08949741388683152 | 1.3676733008667714 |
| 1920 | 18.385920 | 3593 | −0.02628891104945999 | 0.3631155838706661 |

Across all 240 saved times, both the maximum exceeding-cell count (**6953**) and maximum pressure excess (**1.6497336066402084 MPa**) occur at **day 728**. The newly computed portion, days 808–1920, has a peak count of **6538 at day 808**. Continued injection leaves thousands of cells above the limit at day 1920, but this run does **not** support a claim that continued injection causes progressively larger exceedance. These are saved-time extrema, not a claim about unexported internal solver timesteps. No causal mechanism for the declining pressure excess is isolated by this single continuation.

| Selected case | Day1920 q [m³/s, display only] | Day1920 injected mass [Mt] | Day1920 exceeding cells | Peak cells over the 79 movie times |
|---|---:|---:|---:|---:|
| PoF ε=0.0 | 0.07323 | 4.931200512 | 0 | 0 |
| CVaR α=0.01, γ=0.1 | 0.14667 | 13.06217622528 | 0 | 2285 |
| No control, continued | 0.20000 | 18.385920 | 3593 | 6953 |

## Continuation and provenance

The historical `no_control_delayed_ramp_10_periods.jld2` marks `severe_day=728`, the first saved time reaching its legacy minimum-margin threshold −0.1. Its generator finishes that 80-day simulator call before stopping, so it actually contains **100 original eight-day states through day 800**. The new continuation keeps all 100 pressure/saturation fields unchanged and restarts from their last reservoir state at day 800. The first newly simulated output is day 808. Days 728–800 come from the same original no-control forward run, with the same implemented rate.

The saved `full_rates` prescribes a ramp from 0 to 0.2 m³/s over the first ten 80-day rate periods, then 0.2 m³/s through day 1920. We retain those exact floating-point rates and continue periods 11–24. Each simulator call still covers 80 days with ten eight-day outputs; adjacent equal-rate periods are not merged. Reservoir pressure and saturation carry forward; the historical wrapper's well-state initialization behavior at each call boundary is preserved. There are no posterior-state replacements, look-ahead schedule substitutions, threshold recalibrations, or synthetic intermediate fields.

The historical source is array job **9796949_1**, concrete Slurm task **9796952**, confirmed by `logs/out_nc_delay_9796949_1.txt` (ramp, severe day, output filename). New continuation job: **13209163**, requested 8 CPUs / 16 GB / maximum 90 minutes. New data: [no_control_continued_20260914_13209163](../../../data/forward/no_control_continued_20260914_13209163/). Period checkpoint files and streaming diagnostics preserve completed work. Every output is written to a new directory; prior exports remain unchanged.

Source SHA-256: `f7119542ed88cf4e54bd681c2b7843c10a9f4dd17ad5a6ad06565a0b86e101e2`. The new export and validation include the source checksum and verify exact equality of all 100 historical fields. Its runtime provenance records Julia 1.11.3, Jutul 0.2.11, JutulDarcy 0.2.7, JutulDarcyRules 0.2.8, script/manifest hashes, and the repository commit at submission. This is a newly computed continuation with recorded installed dependencies, not a claim that the historical simulator binary was recovered.

## Common physical configuration and source table

All cases use truth slice `BroadK[2000,:,:]` from `data/geo/wise_perm_models_2000_new.jld2` (h5py `[:,:,1999]`), slice SHA-256 `fb6b891d72e6dad08ed1338908fb736922913dbfdc09d9b33df64584724c2246`. Grid: 512×1×256; spacing 6.25×100×6.25 m; depth increases down. Interior porosity is 0.25 and Kv/Kh=0.36. The existing model's boundary pore-volume padding, h=0, pressure convention and initial saturation blob are retained. No flow/fracture constitutive law is changed after exceedance. All saved p0 and pmax arrays match; pmax remains p0+4 MPa. The nominal well marker stays x=1562.5 m, z=1200–1237.5 m.

Pressure is absolute Pa in the simulator. Displayed pressure increase is (p_res−p0)/10⁶ MPa. The separate violation diagnostic is max(0,max(p_res−pmax))/10⁶ MPa; it is not the displayed pressure increase. Relative margin is (pmax−p_res)/pmax and saturation is dimensionless. Simulation times are physical days, 86400 s/day. Injected mass integrates the exact schedule using the historical 700 kg/m³ injection-reference density and excludes initially present CO₂. Rate annotations describe the rate that produced the saved end-of-interval state, with five decimal places only for display.

| Case | Run ID and schedule source | Saved-time range | Data files | Shared grid/units | Shared color limits |
|---|---|---|---|---|---|
| PoF ε=0.0 | Historical 9537372_0, 9523888, 9798781_0; saved `POF_eps0_rates` | Days 8:8:480, then 80-day fields to 1920, plus day728 | `plots/paper_figures/first_step_substeps_POF_eps0.jld2`, `forward_sim_four_steps_base_data.jld2`, `controlled_day728_POF_eps0.jld2` | Common configuration above | r: [−0.1,1]; Δp: [0,5.932220286972219] MPa; S: [0,1] |
| CVaR α=0.01, γ=0.1 | Historical 9820154_1; saved rates equal base CVaR ×1.22 | Days 8:8:1920 | `plots/paper_figures/full_campaign_video_CVaR_g01_a001_sensitivity.jld2` | Common configuration above | Same |
| No control (continued injection) | Historical 9796949_1 / task9796952; continuation13209163; original saved `full_rates`, holding0.2 after ramp | Historical days8:8:800 plus new808:8:1920 | `plots/paper_figures/no_control_delayed_ramp_10_periods.jld2`; `data/forward/no_control_continued_20260914_13209163/no_control_continued.jld2` | Common configuration above | Same |

## Movies and reference consistency

Rendering and full-decode job: **13209288**. Export directory: [p1_continued_reference_movies_20260914_13209288](../../../plots/paper_figures/p1_continued_reference_movies_20260914_13209288/). Four synchronized 40-second / 30-fps / 1200-frame H.264/yuv420p files are produced: one 3840×2160 comparison and three 1280×2160 policy exports. Each has a PNG poster at day1920 and still at day728. Prefer the combined full-slide movie; the individual files share exactly the same clock and duration.

The comparison uses **79 common saved days**, because strict PoF lacks the later eight-day fields between its 80-day snapshots. No t=0 or intermediate state is invented. Saved states repeat in proportion to physical-time gaps; `playback_timeline.json` and `saved_time_validation.csv` record the actual field timestamps. The new no-control diagnostic independently examines **all 240 eight-day states**, including times omitted by the synchronized movie. Thus its full-trajectory peaks are not inferred from the movie sampling.

The prior revision's enlarged maps, fixed axes, well positions, compact headers and short footer are retained. The footer is only “Red cells mean pressure-limit exceedance (r < 0).” The margin equation and sensitivity multiplier are absent from the screen, as requested; their provenance is explicit here and in machine-readable metadata. The no-control heading says “No control (continued).” The combined day8 frame was visually inspected for title, tick, label, colorbar and footer spacing; every frame also checks all text bounds against the canvas.

Color maps and limits match the static reference: 26 Reds_r and 230 Blues entries for margin, colorcet CET_L3_r for pressure increase, cmasher rainforest_r for saturation. The red/blue bin boundary is aligned at exactly r=0. Values outside the static limits remain numerically intact and use explicit colorbar extensions; there is no per-frame scaling or silent data clipping.

Across all displayed cases/times, r spans [−0.1072997467733469, 0.9750584615384615], pressure increase spans [−0.006152097844175994, 5.649733606640209] MPa, and saturation spans [0, 0.89863074967834]. Lower extensions cover the negative pressure increases and margins below −0.1; no displayed pressure increase exceeds the static upper limit, so no upper extension is needed.

Day728 PoF and no-control source fields are unchanged from the corresponding static figure inputs. The historical CVaR time-series and its separate static day728 field use the same 1.22× rates but different simulator-call boundaries: 93 versus97 exceeding cells, maximum pressure difference1921.583988 Pa and saturation difference0.0452719034. The movie retains its continuous historical trajectory rather than replacing a single frame. This existing discrepancy is retained and documented, not corrected by relabeling data.

The September13 rounded 10.71 Mt CVaR value belongs to the unscaled base schedule. The selected sensitivity trajectory instead integrates to **13.06217622528 Mt** at day1920. Strict PoF integrates to **4.931200512 Mt**. Continued no control integrates to **18.38592 Mt**; its original day728 value remains **3.967488 Mt**. There is no PoF ε=0.01 case in this revised selection.

## Reproduction

1. `sbatch scripts/shell/submit/submit_no_control_continuation.sh`
2. After successful continuation, `sbatch --dependency=afterok:FORWARD_JOB scripts/shell/submit/submit_continued_reference_movies.sh data/forward/no_control_continued_20260914_FORWARD_JOB/no_control_continued.jld2`

The forward export script refuses an existing output directory. Rendering similarly creates a new job-specific directory. It validates the original prefix before using the continuation. The independent analysis rederives counts, minimum margin and maximum pressure excess from every saved array, checks achieved continuation well rates against0.2 m³/s, and compares the rederived values to the simulation's diagnostics. The media check fully decodes each movie and requires1200 valid frames.

Caption: “Ground-truth flow-model trajectories for PoF ε=0, CVaR α=0.01, γ=0.1, and no control with continued injection through day1920. Rows show relative margin, pressure increase and CO₂ saturation with fixed shared scales. Red cells indicate pressure-limit exceedance. The no-control continuation retains the original ramp and holds0.20000 m³/s.”

The [earlier static-reference revision](../p1_static_reference_movies_20260914/README.md), [original campaign audit](../p1_control_movies_20260913/delivery_validation.md), and [separate slide2 image-source report](../slide2_source_20260913/README.md) remain available.

## Completed delivery validation

Render/analysis/decode job **13209288 completed successfully in 10 min 13 s**, with maximum resident memory **3,046,292 KiB**. All four movies fully decode to 1200 frames without errors and have the requested dimensions, 40-second duration, 30 fps, H.264 codec and yuv420p format. Their 79 saved-state timestamps agree exactly across all policies, including after day728. The eight poster/still PNGs and additional violation-history PNG open correctly; all twelve renderer media checksums match. The combined first frame, combined and individual day728 frames, combined day1920 poster and violation-history chart were visually inspected without clipping or overlapping labels.

The independent all-time analysis rederived the no-control metrics directly from all 240 pressure arrays, verified the complete time grid and all 100 original pressure/saturation states, and matched the simulation diagnostics. Machine-readable checks are preserved in [validation_summary.json](validation_summary.json), as well as the export's `no_control_continuation_validation.json`, `no_control_all_saved_times.csv`, `media_validation.json`, `decode_validation.json`, and source/frame metadata.

Delivery: [combined 4K MP4](../../../plots/paper_figures/p1_continued_reference_movies_20260914_13209288/comparison.mp4), [violation-history PNG](../../../plots/paper_figures/p1_continued_reference_movies_20260914_13209288/no_control_violation_history.png), and [complete presentation bundle](../../../plots/paper_figures/p1_continued_reference_movies_20260914_13209288/p1_continued_reference_movies_handoff.zip). The bundle contains the four movies, nine PNGs, captions, report and validation records; full simulation arrays and period checkpoints remain in the separately linked data directory.
