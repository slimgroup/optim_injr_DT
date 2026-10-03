# Compact three-row posterior video

The user selected the version retaining absolute pressure and requested reduced
whitespace. Slurm job **13209880** completed the compact 1080p export.

- [Video, 35.84 seconds](../../../plots/posterior_sample_videos/k1_compact_absolute_20260915_v1/with_absolute_pressure/posterior_samples_k1_36s.mp4)
- [PNG poster](../../../plots/posterior_sample_videos/k1_compact_absolute_20260915_v1/with_absolute_pressure/poster.png)
- [Caption and provenance](../../../plots/posterior_sample_videos/k1_compact_absolute_20260915_v1/README.md)

Three rows remain: pressure difference, absolute pressure and saturation. Panels
are enlarged from 508.8 x 253.9 pixels to 536 x 267.5 pixels while preserving
their physical aspect ratio. Column gaps are 16 pixels and row gaps 14 pixels;
header and outer margins are tightened. All spatial data remain displayed.

An explicit comparison with the previous three-row provenance confirms unchanged
source checksum, sample IDs/order, timing, titles, time label, row order and
color limits. The movie still contains all 128 samples, seven frames each at
25 fps: 896 frames and 35.84 seconds. H.264/yuv420p, 1920x1080. Complete decoding
passed with no errors. The 18 original numerical reference checks passed, and
sample 1 and sample 128 layouts were visually reviewed; text and colorbars fit.

The new optional `--compact-absolute` flag renders only this selected layout.
Existing command behavior and all previous exports are preserved. No training,
inference, optimization or simulation is performed.

```bash
sbatch scripts/shell/submit/submit_posterior_presentation_video.sh \
  --compact-absolute --output plots/posterior_sample_videos/NEW_DIRECTORY
```
