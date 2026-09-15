# 20-second comparison with no control held at day 728

The September 15 revision shortens all four movies to **20 seconds**, removes “continued” from the no-control title, moves the bottom explanatory sentence into the header, reduces unused header space and holds no control at its **day-728 pressure-limit-exceedance peak**. The controlled campaigns still advance through day 1920. This uses existing saved fields only; prior data, the continued-injection run, and all earlier movies are preserved.

## When does no control reach 0.20000 m³/s?

The historical `full_rates` first reaches 0.2 at its **10th 80-day rate period**, starting at the **day-720 rate switch**. The day-720 saved state was produced by the preceding rate, 0.17777777777777778 m³/s. The first saved state after the switch is **day 728**, produced at 0.2 m³/s.

| Saved state | Rate that produced the state [m³/s] | Cumulative injected CO₂ [Mt] | Exceeding cells |
|---:|---:|---:|---:|
| Day 720 | 0.17777777777777778 | 3.870720 | 5909 |
| Day 728 | 0.20000000000000000 | 3.967488 | 6953 |

The mass integrates the exact implemented ramp using 86400 s/day and the historical 700 kg/m³ injection-reference density; it excludes the initial saturation blob. Rates are displayed with five decimals without rounding the simulation inputs or mass calculation.

After day 728, the no-control maps and **all their metrics** remain at day 728. Its visible `Day 728 held` badge separates that field time from the common comparison clock. The header uses **q₇₂₈** to identify the injection rate that produced the frozen state; it does not imply ongoing injection after the stop. Its 3.97 Mt display is the cumulative mass at the selected endpoint. The held frame is a presentation of the peak state, not a simulated post-shutdown pressure trajectory. The 18.38592 Mt result from the separate continued-injection run remains valid for that different scenario and is not used here.

## Export and layout

Preview job: **13209871**, completed in 34 seconds. Final render/decode job: **13209904**. Export directory: [p1_peak_hold_movies_20260915_13209904](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13209904/).

- One 3840×2160 comparison MP4 and three 1280×2160 policy MP4s.
- All share 20 seconds, 30 fps and 600 encoded frames, H.264/yuv420p.
- Each has a day-728 PNG and a final-comparison poster. In the final poster, the controlled fields are day 1920 and no control is visibly held at day 728.
- All retain the original axes, depth orientation, injector locations and fixed quantity color scales.
- The only explanatory sentence is now at the top: “Red cells mean pressure-limit exceedance (r < 0).” The margin equation and sensitivity multiplier remain absent from the screen.
- In the combined export, each map's height increases from 0.242 to 0.263333 of the canvas, approximately **8.8%** more map area at the same width. The top of the maps moves from 0.862 to 0.895, using more of the upper canvas. The bottom explanatory-text area is returned to the maps and x-axis labels.

The movie preserves all **79 comparison timestamps** from the previous 1920-day edition and repeats saved frames to make 600 video frames. It starts at the first available day-8 fields. Strict PoF has eight-day outputs through day 480, then only 80-day maps plus its dedicated day-728 state. Thus no missing intermediate fields are interpolated. The no-control column evolves through day 728, then remains fixed while the controlled clock advances. The 16 comparison records at or after day 728 all point to the same no-control pressure/saturation array index 90 (Python indexing).

## Sources and scientific checks

| Case | Run identifiers and schedule | Field files under `plots/paper_figures/` | Displayed endpoint | Mass at displayed endpoint [Mt] | Peak cells at comparison times |
|---|---|---|---:|---:|---:|
| PoF ε=0.0 | 9537372_0, 9523888, 9798781_0; saved `POF_eps0_rates` | `first_step_substeps_POF_eps0.jld2`; `forward_sim_four_steps_base_data.jld2`; `controlled_day728_POF_eps0.jld2` | 1920 | 4.931200512 | 0 |
| CVaR α=0.01, γ=0.1 | 9820154_1; saved CVaR rates ×1.22 | `full_campaign_video_CVaR_g01_a001_sensitivity.jld2` | 1920 | 13.06217622528 | 2285 |
| No control | 9796949_1 / concrete task9796952; original delayed-ramp `full_rates` | `no_control_delayed_ramp_10_periods.jld2`, through day728 | 728 | 3.967488 | 6953 |

All use `BroadK[2000,:,:]` from `data/geo/wise_perm_models_2000_new.jld2`, truth-slice SHA-256 `fb6b891d72e6dad08ed1338908fb736922913dbfdc09d9b33df64584724c2246`. Grid: 512×1×256; cell dimensions 6.25×100×6.25 m; interior porosity 0.25 with the historical boundary padding; Kv/Kh=0.36; h=0. The initial state, absolute-Pa pressure convention, time units and saved p0/pmax arrays are inherited unchanged. Depth increases down and the nominal injector stays x=1562.5 m, z=1200–1237.5 m.

| Quantity | Definition / units | Fixed color limits | Palette |
|---|---|---|---|
| Relative margin | (pmax−p_res)/pmax, dimensionless; pmax=p0+4 MPa | [−0.1,1], explicit lower extension | Static 26 Reds_r +230 Blues colors, sign boundary exactly at zero |
| Pressure increase | (p_res−p0)/10⁶, MPa | [0,5.932220286972219], explicit lower extension | colorcet CET_L3_r |
| CO₂ saturation | Original saved saturation, dimensionless | [0,1] | cmasher rainforest_r |

Negative margins and small negative pressure increases remain numerically intact. No per-frame normalization or value clipping is introduced. Instantaneous cell counts indicate pressure-limit exceedance, not proven fracture/leakage or ensemble/space-time PoF.

Day-728 PoF and no-control fields are the original static-reference inputs. The selected CVaR trajectory keeps the same 1.22× schedule as the static figure but retains the already documented difference in simulator-call boundaries: the video has 93 exceeding cells at day 728, versus 97 in the separate static field; maximum pressure difference 1921.583988 Pa and saturation difference 0.0452719034. No isolated static field is spliced into the time series. The current sensitivity trajectory's final 13.06 Mt is distinct from the unscaled base CVaR manuscript value 10.71 Mt.

## Reproduction and verification

Run `sbatch scripts/shell/submit/submit_peak_hold_movies.sh`; add `--preview-only` to produce the eight layout previews. The wrapper requests 4 CPUs, 12 GB and at most 30 minutes, writing into a new job-specific export directory. It performs no forward simulation. The underlying renderer retains its earlier 40-second default and adds explicit `--seconds 20 --compact-header` options for this revision. The shared decoder retains its 1200-frame default and accepts `--frames 600` for these files.

The preview's combined and individual final posters were visually inspected. Text is checked against canvas bounds and header text boxes are checked for overlap. The source-index CSV verifies that all held no-control records retain the exact day-728 rate, mass and count. Source hashes, time coverage and fixed scales are recorded in `validation.json`; `playback_timeline.json` records all frame repeats and source timestamps. Each final MP4 is fully decoded and must contain exactly 600 frames.

Caption: “Ground-truth flow-model comparison of PoF ε=0, CVaR α=0.01, γ=0.1, and no control. Controlled campaigns advance to day 1920; no control is held at its day-728 pressure-limit-exceedance peak, with 3.97 Mt injected. Rows show relative margin, pressure increase and CO₂ saturation on fixed shared scales.”

The [continued-injection result and validation](../no_control_continuation_20260914/README.md) and [earlier static-reference movie report](../p1_static_reference_movies_20260914/README.md) remain available for their respective scenarios.

## Completed delivery validation

Job **13209904 completed successfully in 9 min 13 s**, with maximum resident memory **2,525,928 KiB**. All four MP4s fully decoded without errors and contain exactly **600 frames at 30 fps / 20 seconds**, H.264/yuv420p, with the expected 3840×2160 or 1280×2160 dimensions. All eight PNGs open correctly and all twelve media checksums match.

The no-control map areas were compared pixel by pixel across all 16 comparison records from day728 through the final clock. Both the combined and individual exports preserve exactly identical map pixels throughout the hold. PoF and CVaR map pixels change between day728 and day1920, confirming that only the intended case is frozen. Held source indices and metrics also agree in every CSV row. The day728 record first appears at video frame226 (approximately7.533 seconds); frame repeats then follow the common physical-time spacing. Final combined and individual no-control posters match the visually inspected preview exactly.

Detailed records are in [validation_summary.json](validation_summary.json) and the export's `media_validation.json`, `decode_validation.json`, `saved_time_validation.csv`, and `playback_timeline.json`.

Files: [4K comparison MP4](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13209904/comparison.mp4), [final poster](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13209904/comparison_poster.png), and [complete delivery ZIP](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13209904/p1_peak_hold_movies_handoff.zip). The ZIP includes four videos, eight PNGs, concise captions, the source report and validation records.
