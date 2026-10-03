# Static-reference movie revision — 2026-09-14

The September 14 request changes the cases to **PoF ε=0.0; CVaR α=0.01, γ=0.1; no control**, in that order, and selects the same CVaR **1.22× sensitivity schedule** used by the existing spatial figure. This supersedes the September 13 three-controlled-case selection for this export. The former movies and scientific inputs remain intact.

The revision reuses the static figure's palettes and fixed scale limits, enlarges each map in the combined export by approximately 36% in area, and shares one colorbar per quantity. The screen contains one common day/monitoring-step heading, a case heading, and one short line showing actual implemented injection rate, cumulative mass and exceeding-cell count. The margin equation and minimum-margin annotation are removed from the screen; their values/definitions remain in validation metadata. The only footer is “Red cells mean pressure-limit exceedance (r < 0).” No sensitivity multiplier is displayed on-screen, as requested; its provenance remains explicit here and in the script/metadata. The rate and mass annotations use the actual sensitivity schedule, not the unscaled numbers displayed by the old static figure.

## Export and playback

Output directory: [p1_static_reference_movies_20260914_13208794](../../../plots/paper_figures/p1_static_reference_movies_20260914_13208794/).

- [Combined 4K movie](../../../plots/paper_figures/p1_static_reference_movies_20260914_13208794/comparison.mp4): 3840×2160.
- [PoF ε=0.0](../../../plots/paper_figures/p1_static_reference_movies_20260914_13208794/pof_eps0.mp4), [CVaR](../../../plots/paper_figures/p1_static_reference_movies_20260914_13208794/cvar_alpha001_gamma01.mp4), [no control](../../../plots/paper_figures/p1_static_reference_movies_20260914_13208794/no_control.mp4): 1280×2160 each.
- Each export has a PNG poster and day-728 still. Both represent day 728 in this edition.
- Four movies share exactly 40 seconds, 30 fps and 1200 encoded frames, H.264/yuv420p. Prefer one combined full-slide movie; individual exports have identical playback timing.

**This edition ends at day 728**, the end of the selected no-control record. It shows **64 common saved states**: days 8,16,…,480; 560,640,720,728. Strict PoF has no eight-day spatial exports for the intervening later times. No t=0 or interpolated states were introduced. Midpoint-based display intervals, rounded to video frames, repeat each actual saved state in proportion to physical spacing; the displayed clock always gives the saved field's day. The source-index CSV and playback timeline explicitly record all times.

No new forward simulation, optimization or training was run. The original no-control file contains data through day 800, but its selected historical stop at day 728 is honored. The separate historical post-shutdown full-campaign no-control simulation is not substituted. The renderer also supports `--end-day 1920`: controlled fields continue while no control is held at its explicitly labelled day-728 endpoint. That mode is available for a subsequent user preference; this delivery uses the common 728-day interval.

## Sources and scientific checks

| Case | Spatial source files under `plots/paper_figures/` | Implemented schedule / historical identity | Day 728, actual q (m³/s) | Day 728 mass (Mt) | Day 728 exceeding cells | Peak over movie's saved states |
|---|---|---|---:|---:|---:|---:|
| PoF ε=0.0 | `first_step_substeps_POF_eps0.jld2`; `forward_sim_four_steps_base_data.jld2`; `controlled_day728_POF_eps0.jld2` | Saved `POF_eps0_rates`; historical jobs 9537372_0, 9523888 and 9798781_0 | 0.03745 | 0.837019008 | 0 | 0 |
| CVaR α=0.01, γ=0.1 | `full_campaign_video_CVaR_g01_a001_sensitivity.jld2` | Saved eight-day rates equal base CVaR rates ×1.22; historical full-trajectory job 9820154_1 | 0.1208532 | 2.849694317568 | 93 | 2285 |
| No control | `no_control_delayed_ramp_10_periods.jld2`, through saved `severe_day=728` | Saved delayed-ramp `full_rates`; rate producing the final state is 0.2 | 0.2 | 3.967488 | 6953 | 6953 |

Rates display with five decimal places but are read and integrated without rounding. Cumulative mass integrates the actual rate over elapsed physical days using 86400 s/day and the historical injection-control reference density 700 kg/m³; it excludes the initial saturation blob. At rate boundaries, the annotation is the rate that produced the saved end-of-interval state. `implemented_rates.csv` preserves actual numerical schedule values.

The common truth is `data/geo/wise_perm_models_2000_new.jld2`, Julia `BroadK[2000,:,:]`, h5py `[:,:,1999]`. Slice SHA-256: `fb6b891d72e6dad08ed1338908fb736922913dbfdc09d9b33df64584724c2246`. Every source's saved ground-truth index, p0 and pmax agree. Grid: 512×1×256; spacing 6.25×100×6.25 m; h=0; interior porosity 0.25 with inherited pore-volume padding. The fixed initial saturation blob, absolute-Pa simulator pressure convention, index-depth hydrostatic reference and well initialization/call boundaries are preserved. Configuration details and remaining historical provenance limits are in the [earlier complete audit](../p1_control_movies_20260913/delivery_validation.md) and [BHP audit](../../historical/analysis/BHP_GROUND_TRUTH_AUDIT_2026-09-07.md).

Fields use the original `(z,x)` orientation, depth increasing down, full extent x=0…3193.75 m, z=0…1593.75 m. The nominal injector marker remains x=1562.5 m, z=1200…1237.5 m. Pressure limit is pmax=p0+4 MPa. Quantities remain r=(pmax−p_res)/pmax, pressure increase=(p_res−p0) in MPa, and saved CO₂ saturation. No field values were modified.

Strict PoF snapshots at days 80…480 agree exactly with its first-interval file and are deduplicated. Its dedicated day-728 export continues the preceding saved ground-truth state. CVaR uses one continuous saved sensitivity trajectory throughout; no posterior updates or single-frame replacements are inserted.

## Static figure comparison and colorbars

Reference: `fracture_comparison_3x3_four_steps.png`, generated by `scripts/python_plots/plot_real_fracture_comparison_day408.py` with `CVAR_SENSITIVITY=1.22`.

| Quantity | Fixed limits in every case/frame | Palette / handling |
|---|---|---|
| Relative margin r | −0.1 to 1 | Same 26 Reds_r and 230 Blues color entries as the static figure. Bin edges are aligned exactly at r=0 so red denotes only negative margin. Values below −0.1 use the red under-range color and a lower colorbar extension; they are retained numerically. |
| Pressure increase | 0 to 5.932220286972219 MPa | Static `colorcet.CET_L3_r`; exact static day-728 maximum ×1.05. Negative values remain in source/metrics and use the white endpoint with an explicit lower colorbar extension. |
| CO₂ saturation | 0 to 1 | Static `cmasher.rainforest_r`. |

The original static margin implementation uses a linear range and a 26/256 red fraction, which places its red/blue transition slightly above zero. This revision retains its palette and limits while aligning that transition at zero to make the requested red-cell statement accurate. Consequently, some near-zero positive cells have a different color from that historical PNG. Colorbars remain fixed; there is no per-frame normalization or numeric clipping.

Global displayed field ranges: r=[−0.1072997467733469,0.9750584615384615], pressure increase=[−0.006152097844175994,5.649733606640209] MPa, saturation=[0,0.8960740403157991]. Only the explicitly marked under-range portions fall outside the static colorbar intervals.

**CVaR's static day-728 file and historical video file are distinct numerical trajectories with the same ×1.22 schedule.** The static file `cvar_day728_sensitivity_1p22x.jld2` has 97 exceeding cells; the video's Float32 field has 93. Their maximum absolute differences are 1921.583988 Pa in pressure and 0.0452719034 in saturation. The original generators differ in merging adjacent equal-rate simulator calls, with well state reinitialized at call boundaries. This was already documented in the BHP audit. The movie preserves its consistent time-series fields rather than inserting the static file at one time. PoF and no-control day-728 fields match the static figure's respective sources.

Instantaneous cell counts indicate pressure-limit exceedance, not proven fracture/leakage, ensemble probability or space-time PoF. Minimum margin remains available in the CSV; maximum normalized pressure is mathematically redundant with it and is not added to the screen.

## Validation and reproduction

The output contains `validation.json` (input hashes, configuration, time coverage, static comparison and extrema), `saved_time_validation.csv` (192 case/time rows), `implemented_rates.csv`, `playback_timeline.json`, `output_checksums.json`, and a full-decode validation record. PNG layouts were visually checked; every rendered text object's bounds are checked against the canvas to detect clipping. The preliminary preview with insufficient spacing is preserved separately; the reviewed preview is job 13208744.

Renderer: [create_static_reference_movies.py](../../../scripts/python_plots/create_static_reference_movies.py). Submit with `sbatch scripts/shell/submit/submit_static_reference_movies.sh`; optional `--preview-only` renders day-728 PNGs. The wrapper allocates 4 CPUs, 12 GB, maximum 90 minutes, creates a new job-specific directory and runs no Julia. The output directory must not already exist. Media validation runs through `scripts/python_tools/analysis/validate_selected_control_media.py` on a Slurm node.

The earlier [three-controlled-case renderer/report](../p1_control_movies_20260913/README.md) remains available. The image provenance research remains in its [separate report](../slide2_source_20260913/README.md); no new image-source claim is made in this revision.

Caption: “Ground-truth time evolution for PoF ε=0, CVaR α=0.01, γ=0.1, and no control. Rows show relative margin, pressure increase and CO₂ saturation with fixed shared scales. Red cells indicate pressure-limit exceedance. Shown through the no-control endpoint at day 728 using common saved times.”

Completed validation: render job **13208794** finished in **7 min 49 s**; decode job **13208951** finished in **18 s**. All four movies decoded all 1200 frames without errors and report 40 seconds / 30 fps, H.264/yuv420p. Dimensions and all twelve media/still-image SHA-256 values were verified.
