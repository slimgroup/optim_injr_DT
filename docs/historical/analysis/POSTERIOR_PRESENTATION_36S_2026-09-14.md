# Posterior presentation revision — approximately 36 seconds

The requested presentation changes are complete in Slurm job **13209127**.
Both versions use all 128 saved k=1 posterior samples, seven display frames per
sample at 25 fps, giving **35.84 seconds**. Samples retain original order and
within-case pressure/saturation pairing. No sample interpolation or blending.

- [Recommended: pressure difference and saturation](../../../plots/posterior_sample_videos/k1_presentation_36s_20260914_v1/pressure_difference_saturation/posterior_samples_k1_36s.mp4)
- [Matched comparison retaining absolute pressure](../../../plots/posterior_sample_videos/k1_presentation_36s_20260914_v1/with_absolute_pressure/posterior_samples_k1_36s.mp4)
- [Posters, caption and provenance](../../../plots/posterior_sample_videos/k1_presentation_36s_20260914_v1/README.md)

The title is now **Posterior samples**. The explanatory footer is removed.
The time is displayed as **Monitoring step k=1 | Day 480**, following the
repository timeline, the user's earlier corroboration and their request to
remove “nominal”. No embedded export timestamp has been recovered. Original
observation IDs and upstream preprocessing remain unconfirmed in provenance.

The recommended layout omits absolute pressure. For a fixed p0, absolute
pressure and p-p0 contain the same sample-dependent pressure information.
Subtracting the hydrostatic background makes local variation easier to see.
The comparison version retains absolute pressure so this presentation decision
can be reviewed with identical samples and playback speed.

Fixed color limits, full spatial extent, downward depth direction and physical
aspect ratio are retained. Source checksums and all 18 original mean/std
reference arrays match exactly. Both 1920x1080 H.264/yuv420p movies passed full
896-frame decoding and metadata checks. Text overlap, canvas bounds, equal
panel sizes and aligned colorbars were checked; representative frames from both
layouts were visually reviewed. Slurm stderr is empty.

All previous data and media remain intact. The new renderer uses the existing
audited helpers, with source snapshots in the new delivery. No simulation,
training, inference or optimization was run.

```bash
sbatch scripts/shell/submit/submit_posterior_presentation_video.sh \
  --output plots/posterior_sample_videos/NEW_DIRECTORY
```
