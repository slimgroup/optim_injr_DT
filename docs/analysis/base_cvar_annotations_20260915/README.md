# Original-schedule CVaR annotations

The September 15 follow-up requests the original CVaR injection-rate and cumulative-mass labels while retaining the accepted maps, 20-second duration and layout. The display now reads the saved unscaled `CVaR_g01_a001_rates` array directly from `plots/paper_figures/forward_sim_four_steps_base_data.jld2`.

The CVaR pressure, saturation, relative-margin maps and exceeding-cell counts still come from `full_campaign_video_CVaR_g01_a001_sensitivity.jld2`: the simulation uses 1.22 times that base schedule over all four monitoring intervals. Therefore, the displayed base rate and mass do **not** represent the implemented inputs and integrated injected mass of the displayed CVaR fields. The presenter requested this distinction and will explain it. It is recorded here and in the caption and machine-readable export; the compact on-screen labels retain their established format.

| Day-1920 CVaR quantity | Original schedule shown in annotations | Schedule used to simulate the displayed fields |
|---|---:|---:|
| Injection rate [m³/s] | 0.12022 | 0.1466684 |
| Cumulative mass [Mt] | 10.706701824 (shown as 10.71) | 13.06217622528 (previously shown as 13.06) |

Rates are read at full precision. For each physical day, cumulative mass is integrated from the original piecewise constant 80-day rate array with 86400 seconds/day and 700 kg/m³, matching the existing conversion. The saved-output convention remains (start, end]: a field at a rate boundary is labelled with the rate producing that field. Only the presentation annotation accessor chooses the base schedule; simulation metrics and source data are unchanged.

PoF and no-control rate/mass labels continue to describe their implemented schedules. No control evolves through day 728 and then holds the saved fields and all metrics, with its visible hold badge. Its final label remains q₇₂₈=0.20000 m³/s and 3.97 Mt.

## Reproduction and source records

The existing renderer defaults to the implemented values. Explicitly request the new presentation using:

```bash
sbatch scripts/shell/submit/submit_peak_hold_movies.sh --cvar-annotation-schedule base
```

Render/decode Slurm job: **13243536**. New output: [p1_peak_hold_movies_20260915_13243536](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13243536/). Existing exports are preserved; no forward simulation or optimization is run.

- `annotation_values.csv`: all 237 case/time rows, with displayed rate/mass beside implemented rate/simulated mass and an explicit annotation-schedule field.
- `saved_time_validation.csv`: unchanged simulation-derived metrics and field references for all 79 common saved times.
- `implemented_rates.csv`: unchanged actual simulation inputs.
- `validation.json`: source hashes, case order, grid, color scales, field extrema, and explicit annotation provenance.
- `playback_timeline.json`: the synchronized saved-state timing for all four exports.

Source-run identifiers, shared ground-truth/grid/units, fixed color scales and the known static/day-728 CVaR discrepancy remain documented in the [previous centered-movie report](../centered_control_movies_20260915/README.md). The current revision changes only the two CVaR numeric annotations.

Caption: “PoF, CVaR and no-control flow-model evolution. CVaR rate and cumulative-mass labels report the original base schedule; its displayed fields and cell counts use the saved 1.22×-rate sensitivity simulation. No control is held at its day-728 pressure-limit-exceedance peak after that time. Red denotes r<0.”

## Completed validation and delivery

Job **13243536** completed in **8 minutes 45 seconds**, with exit status 0 and a maximum resident set of 3,090,816 KiB. All four H.264/yuv420p MP4s passed complete decoding: 600 frames, 30 fps, 20 seconds. The comparison is 3840×2160 and individual exports are 1280×2160. All media checksums pass.

Independent decimal integration verified the original-schedule annotations at all 79 CVaR saved times. The other 158 case/time rate/mass annotations match their implemented values exactly. The scientific metric CSV, implemented-rate CSV and playback timeline are byte-identical to the preceding export. Source hashes, shared scales, grid, day-728 metrics, field extrema and peak cell counts also match.

All eight posters/stills were compared with the previous export. Every map, axis and colorbar is pixel-identical; changed pixels in the comparison and CVaR PNGs are confined to the numeric annotation row. PoF and no-control PNGs are entirely pixel-identical. The day-728 comparison and final comparison poster were visually inspected. The final CVaR labels read **0.12022 m³/s** and **10.71 Mt**. See [validation_summary.json](validation_summary.json) and [annotation_values.csv](annotation_values.csv).

- [4K comparison MP4](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13243536/comparison.mp4)
- [CVaR individual MP4](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13243536/cvar_alpha001_gamma01.mp4)
- [Comparison poster](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13243536/comparison_poster.png)
- [Day-728 comparison still](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13243536/comparison_day728.png)
- [Complete package](../../../plots/paper_figures/p1_peak_hold_movies_20260915_13243536/p1_base_cvar_annotations_handoff.zip)
