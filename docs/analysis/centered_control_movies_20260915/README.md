# Centered-title control movies and full-campaign CVaR scaling check

This September 15 revision enlarges and centers the main day/monitoring-step heading, tightens the spacing between policy annotations and maps, slightly enlarges the other text, and places the short **“Red: r < 0”** note inside each of the three top-row relative-margin panels. The accepted 20-second playback and day-728 no-control hold are retained.

## CVaR scaling applies to all four monitoring steps

The selected historical CVaR export uses **1.22× the base injection rates for the complete 0–1920-day campaign**. It is not restricted to the first two monitoring steps. All 240 saved eight-day rate entries were checked against the base rates; every entry equals the corresponding base rate ×1.22 exactly in the stored floating-point representation.

The historical generator [run_full_campaign_video_cases.jl](../../../scripts/julia_scripts/data_collection/forward_exports/run_full_campaign_video_cases.jl) constructs `repeat(CVAR_BASE_RATES .* CVAR_SENSITIVITY; inner=DS)`, with `CVAR_SENSITIVITY=1.22`, then uses those rates as well inputs for the forward simulation. Pressure and saturation in the movie are the original saved simulation fields. They are **not multiplied by 1.22 during plotting**. The pressure threshold remains pmax=p0+4 MPa.

| Monitoring step | Physical interval [days] | Injection-rate multiplier | Injected mass in interval [Mt] |
|---:|---|---:|---:|
| 1 | 0–480 | 1.22 | 1.3245990912 |
| 2 | 480–960 | 1.22 | 3.36450530304 |
| 3 | 960–1440 | 1.22 | 4.14285484032 |
| 4 | 1440–1920 | 1.22 | 4.23021699072 |

The full trajectory integrates to **13.06217622528 Mt**, displayed as 13.06 Mt. The earlier unscaled base CVaR trajectory integrates to about 10.71 Mt and is a different schedule. Reduced or absent late-time exceedance in the selected movie does not indicate that scaling was disabled after step 2; it is the saved pressure result under the scaled schedule. The rate-by-rate checks and actual first/last rates in each interval are recorded in [cvar_scaling_check.csv](cvar_scaling_check.csv).

## Layout and export

Preview job: **13211172**, completed in 26 seconds. Final render/decode job: **13211190**. Output directory: [p1_peak_hold_movies_20260915_13211190](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13211190/).

| Element | Previous compact export | This revision |
|---|---|---|
| Combined main heading | 21 pt, left aligned | 28 pt, centered |
| Individual main heading | 17 pt, below a note | 21 pt, centered at the top |
| Policy headings | 22 /20 pt, combined/individual | 23 /21 pt |
| Per-case metrics | 14 /11 pt | 15 /12 pt |
| Axis ticks | 15 pt | 16 pt |
| Colorbar ticks | 14 /11 pt | 15 /12 pt |
| Exceedance note | Long sentence in the figure header | Short note inside each top-row map |

The combined statistic row is moved closer to the maps while retaining the map dimensions from the preceding revision. Individual maps gain the space released by the removed header note. The top-row short note sits at the upper left; no control's `Day 728 held` badge remains at the upper right. All text stays within the canvas and header text boxes are checked for overlap. Combined and individual no-control final posters and the individual CVaR day-728 preview were visually inspected.

The export contains one 3840×2160 comparison movie and three 1280×2160 individual movies. All are 20 seconds, 30 fps, 600 frames, H.264/yuv420p, with identical playback timing. Each has a day-728 PNG and final-comparison poster. The comparison uses the same 79 common saved times; it repeats real saved frames without creating intermediate simulation fields.

## Source and endpoint checks

| Case | Historical runs and spatial files under `plots/paper_figures/` | Schedule | Displayed endpoint | Endpoint mass [Mt] | Peak exceeding cells at comparison times |
|---|---|---|---:|---:|---:|
| PoF ε=0.0 | 9537372_0,9523888,9798781_0; `first_step_substeps_POF_eps0.jld2`, `forward_sim_four_steps_base_data.jld2`, `controlled_day728_POF_eps0.jld2` | Saved `POF_eps0_rates` | 1920 | 4.931200512 | 0 |
| CVaR α=0.01,γ=0.1 | 9820154_1; `full_campaign_video_CVaR_g01_a001_sensitivity.jld2` | Base rates ×1.22 in all four intervals | 1920 | 13.06217622528 | 2285 |
| No control | 9796949_1 / task9796952; `no_control_delayed_ramp_10_periods.jld2` | Original delayed ramp through day728 | 728, held afterward | 3.967488 | 6953 |

The no-control ramp switches to 0.20000 m³/s at day 720; day 728 is its first saved output at that rate. Its fields and annotations remain at day 728 when the controlled clock advances. The displayed q₇₂₈ is the rate producing the held state, not ongoing injection. This held peak presentation is distinct from the separately preserved continued-injection and post-shutdown simulations.

All inputs use the common permeability `BroadK[2000,:,:]` from `data/geo/wise_perm_models_2000_new.jld2`, slice SHA-256 `fb6b891d72e6dad08ed1338908fb736922913dbfdc09d9b33df64584724c2246`. The common grid is 512×1×256 with 6.25×100×6.25 m cells, interior porosity 0.25 and the original boundary padding. The saved initial-state conventions, well location, absolute-Pa pressure, depth orientation and p0/pmax arrays are preserved. Only figure layout and typography change in this revision.

Fixed color limits remain r=[−0.1,1], pressure increase=[0,5.932220286972219] MPa and saturation=[0,1]. The palettes remain the static-reference Reds_r/Blues margin map, colorcet CET_L3_r pressure map and cmasher rainforest_r saturation map. The red boundary is exactly r=0; lower colorbar extensions explicitly cover out-of-range values without modifying them. Counts describe instantaneous pressure-limit exceedance, not proven fracture/leakage or ensemble probability.

The existing CVaR day-728 discrepancy remains documented: the selected continuous video trajectory has 93 exceeding cells versus 97 in the separate static field, despite the same 1.22× rates, due to different historical simulator-call boundaries. Maximum pressure and saturation differences are 1921.583988 Pa and 0.0452719034. No replacement static frame is spliced into the trajectory. PoF and no-control day-728 source fields remain the exact static-reference inputs.

Reproduce using `sbatch scripts/shell/submit/submit_peak_hold_movies.sh`; append `--preview-only` for the layout preview. The job writes a new directory and requests 4 CPUs, 12 GB and at most 30 minutes. Earlier movies, source data and simulation outputs are preserved. No forward simulation, training or optimization is needed for this revision. Prior source/timing details remain in the [20-second peak-hold report](../peak_hold_movies_20260915/README.md).

Caption: “Ground-truth flow-model evolution for PoF ε=0, CVaR α=0.01, γ=0.1, and no control. Controlled campaigns advance to day 1920; no control is held at its day-728 pressure-limit-exceedance peak with 3.97 Mt injected. Top-row red cells denote r<0. Rows show relative margin, pressure increase and CO₂ saturation on fixed shared scales.”

## Completed validation and delivery

Slurm job **13211190** completed successfully in **8 minutes 39 seconds**, using a peak resident memory of 2,541,156 KiB. All four MP4s passed complete decoding with exactly 600 frames and no decoder errors. Stream headers confirm 20 seconds, 30 fps, H.264 and yuv420p at the requested resolutions. All eight PNGs have the expected dimensions, and every exported media checksum matches its manifest.

The saved-time CSV, injection-rate CSV and playback timeline are byte-identical to the preceding accepted 20-second export. Source-file records, shared color limits, day-728 checks and displayed extrema also match. All 16 saved no-control panels from day 728 onward are pixel-identical within the new export, while the controlled panels continue evolving. The inspected preview and final PNGs are pixel-identical. These checks are recorded in [validation_summary.json](validation_summary.json).

- [4K comparison MP4](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13211190/comparison.mp4)
- [Comparison poster](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13211190/comparison_poster.png)
- [Day-728 comparison still](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13211190/comparison_day728.png)
- [Complete package: four MP4s, eight PNGs, captions and validation](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13211190/p1_centered_control_movies_handoff.zip)
