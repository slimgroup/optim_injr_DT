# Combined posterior sample video — 2026-09-14

Created the requested 3x3 comparison from existing k=1 posterior arrays on
Slurm job **13208743**, without running inference, optimization or simulation.

[Full 96-second video](../../../plots/posterior_sample_videos/k1_all_cases_20260914_v1/posterior_all_cases_k1_full.mp4),
[24-second talk version](../../../plots/posterior_sample_videos/k1_all_cases_20260914_v1/posterior_all_cases_k1_talk.mp4),
[PNG poster](../../../plots/posterior_sample_videos/k1_all_cases_20260914_v1/poster.png),
[provenance and caption](../../../plots/posterior_sample_videos/k1_all_cases_20260914_v1/README.md).

Columns match the supplied reference: PoF epsilon=0 (X_post1), PoF epsilon=0.01
(X_post2), and CVaR alpha=0.01 gamma=0.1 (X_post3). Rows are pressure difference,
absolute pressure and CO2 saturation. Each row uses one fixed, shared colorbar.

| Row | Computation | Fixed limits |
|---|---|---|
| Pressure difference | (pressure - pres_Hyd) / 1e6 | -0.2 to 5.2 MPa |
| Absolute pressure | pressure / 1e6 | 0 to 18 MPa |
| Saturation | saved saturation channel | 0 to 0.9 |

The full video shows all 128 stored sample indices in order, held for 0.75 s
each. The talk version uses the previous fixed 32-index subset. At index m,
each column displays that case's own joint pressure/saturation sample m;
matching indices across cases do not assert identical physical realizations.
Only sample index changes; monitoring time and case remain fixed. This is not
an animation of physical plume evolution or a new fracture-risk estimate.

Source: `data/posterior/three_set_posteriro_samples_t1_pof_cvar.jld2`.
The source hash still matches the manuscript handoff. All 18 historical numeric
mean/std checks passed exactly (float32, ddof=0), and all plotted values fall
within the fixed limits without clipping or replacement. The original grid
orientation, physical aspect ratio and plotting extent are preserved.

Both streams are 1920x1080 H.264/yuv420p at 24 fps. Complete decoding verified
2304 frames/96 s and 576 frames/24 s. Layout checks cover all text, nine panel
sizes and row-colorbar alignment; sample 1 and sample 128 were visually reviewed.

The user identifies colleague Abhinav as the posterior producer and considers
the day-480 time, case mapping and joint pairing correct. The original file has
no timestamp, observation IDs or upstream preprocessing metadata. The video
retains the label `Nominal day 480`; the remaining provenance limits are
recorded in `combined_provenance.json`. No well geometry was invented.

Existing individual-case videos, historical figures, samples and slides remain
unchanged. The new renderer imports the original audited source/encoding helpers.
Both Python sources and the new Slurm wrapper are snapshotted with the delivery.

```bash
sbatch scripts/shell/submit/submit_posterior_all_cases_video.sh \
  --output plots/posterior_sample_videos/NEW_DIRECTORY
```
