# Posterior pressure/saturation sample videos — k=1

Completed on Slurm job **13165831** using only existing posterior arrays. No
training, inference, optimization or reservoir simulation was run. Existing
mean/std slides, schedules, data and historical outputs were preserved.

Delivery: [README and links](../../../plots/posterior_sample_videos/k1_20260913_v2/README.md),
[provenance table](../../../plots/posterior_sample_videos/k1_20260913_v2/provenance.csv),
[numeric audit](../../../plots/posterior_sample_videos/k1_20260913_v2/audit.json),
[video validation](../../../plots/posterior_sample_videos/k1_20260913_v2/videos.json).

| Case | JLD2 dataset | Samples | Full | Talk |
|---|---|---:|---:|---:|
| PoF epsilon=0.01 | X_post2 | 128 | 96 s | 24 s |
| PoF epsilon=0 | X_post1 | 128 | 96 s | 24 s |
| CVaR alpha=0.01, gamma=0.1 | X_post3 | 128 | 96 s | 24 s |

All videos are 1920x1080, H.264/yuv420p, 24 fps. Each sample is held for
18 frames (0.75 s), with hard cuts. Full videos retain samples 1–128 in stored
order; talk videos use `rint(linspace(1,128,32))`, selected by index without
inspecting fields. Sample 1 is the poster for each case. Pressure and saturation
always share the same index within a case. Cross-case sample identity is not
asserted, and no permeability partner is assigned.

## Source and checks

Source: `data/posterior/three_set_posteriro_samples_t1_pof_cvar.jld2`.
Its SHA-256 matches the latest local manuscript handoff,
`posterior_appendix_e_handoff_ecdf_only_20260909`. That handoff explicitly maps
this source to `state_mean_pressurediff_pressure_sat_all_cases_t1.png` and
`state_std_pressurediff_pressure_sat_all_cases_t1.png`.

All 18 saved numeric reference arrays were reproduced **exactly**: three cases,
three variables (absolute pressure, pressure increment, saturation), mean and
population std (`ddof=0`). Float32 arithmetic and display conversion before
reduction match the original plotter. Pressure and pressure-increment standard
deviations are mathematically redundant, apart from floating-point rounding.

h5py layout is `(128,2,256,512)` = `(sample,variable,z,x)`; channel 0 is saturation,
channel 1 absolute pressure in Pa. Only Pa-to-MPa conversion is applied.
The Julia source layout is `(512,256,2,128)`; no transpose or flip is needed
for h5py fields. The hydrostatic field increases by 62,500 Pa per depth row,
confirming the original orientation. Saved exports are already in physical
units; inverse normalization is not reapplied.

Shared color limits are 0–18 MPa and 0–0.9 saturation. All values are finite;
no saturation value is outside [0,1]. No clipping, filtering, per-frame
normalization, synthetic samples or interpolation between samples is applied.
Original spatial plotting extent and downward depth orientation are preserved:
x=0–3193.75 m and depth=0–1593.75 m, with 6.25 m cells. This is the historical
plotting extent rather than a new cell-boundary convention.

All six streams passed full-frame decoding, codec/pixel-format, resolution,
fps, duration and frame-count checks. Representative PNGs from all three cases
were visually reviewed; text fits and panels/colorbars align.

## Remaining provenance limitations

- Frame titles say **Nominal day 480**. The repository maps k=1 to six 80-day
  control periods, and the risk-trajectory plot marks 480 as the first boundary.
  The JLD2 itself has no timestamp. This is a documented campaign-time mapping,
  not independent verification of the original inference timestamp.
- Original observation IDs, conditioning measurements, checkpoint, and upstream
  inference/export code are not available locally. Case-specific arrays are kept
  fixed; original conditioning identity and upstream preprocessing cannot be
  independently audited from this four-dataset file.
- Source mean/std figures have no well markers, and the export has no well
  geometry. Videos retain no overlays rather than invent well/permeability data.
- The current deck and manuscript document were not accessible here. Source
  figures were resolved via the latest local handoff manifest; no slides changed.
- Absolute-pressure contrasts are partly hidden by the hydrostatic gradient.
  An optional separately labeled `p-p0 [MPa]` video could improve visibility;
  it was not substituted for absolute pressure.

The videos show posterior-state uncertainty. They do not isolate permeability,
show physical plume motion, estimate a new fracture probability, or demonstrate
actual fracture. See the exported compact caption and detailed provenance.

## Reproduce

```bash
sbatch scripts/shell/submit/submit_posterior_sample_video.sh \
  --output plots/posterior_sample_videos/NEW_DIRECTORY
```

The renderer refuses an existing output directory and verifies source/reference
checksums before export. Source scripts used for the completed render are
snapshotted in the delivery's `provenance/` subdirectory. The first failed layout
attempt under `k1_20260913_v1/` is retained; `v2` is the complete delivery.
