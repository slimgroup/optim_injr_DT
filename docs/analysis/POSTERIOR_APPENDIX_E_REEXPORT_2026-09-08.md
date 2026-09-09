# Posterior and Appendix E re-export

## Current statistical presentation (2026-09-09)

The user requested removal of the purple histogram interval and the legend
entry `95% bootstrap interval for the 1% quantile` from steps 2–4. The ECDF
pointwise confidence intervals, all titles, sample-quantile lines and numerical
annotations remain unchanged. The hidden historical interval coordinates remain
in the numerical audit; only their visibility changes. Bootstrap settings stay
at the historical 5,000 replicates and seed 42; this is not a statistical update.

The current complete delivery is
`plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909/` and its
same-stem ZIP. The eight posterior figures are byte-identical copies from the
previous titled delivery. Only the three statistical figures are re-rendered.
Canonical filenames and all `paper_compat/` basenames are unchanged. The previous
titled delivery and its ZIP remain preserved.

Reproduce this presentation update on a compute node, using a fresh output path:

```bash
sbatch scripts/shell/submit/submit_posterior_appendix_e_export.sh \
  --no-publish \
  --reference-handoff plots/paper_figures/posterior_appendix_e_handoff_titles_20260908_verified \
  --reference-change hide-quantile-interval \
  --reuse-posterior-from-reference \
  --handoff-dir plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909
```

The exporter verifies unchanged scientific details and numeric arrays, plus
identical statistical PNG pixels outside the removed shading and shared legend.
Publication backs up only changed canonical files and skips byte-identical ones.
The earlier title-restoration record below describes the previous delivery.

## Current title requirement (supersedes the original request)

The user explicitly restored global titles after reviewing the first handoff.
Every canonical export must now identify the quantity/statistic and monitoring
step using `k`, not `t`: `Posterior mean at monitoring step k=K`,
`Posterior standard deviation at monitoring step k=K`, or
`Injection-rate endpoint histogram and ECDF at monitoring step k=K`.

The exporter adds a 0.5-inch title area above the existing figure canvas. It
does not shrink or move any existing panels, annotations, legends, labels or
colorbars. All canonical and paper-compatibility basenames stay unchanged.
The first title-free handoff and archive remain preserved as prior versions;
the titled handoff supersedes their artwork for paper intake.
The titled delivery directory is
`plots/paper_figures/posterior_appendix_e_handoff_titles_20260908_verified/`; its ZIP uses
the same stem. Canonical figure stems and `paper_compat/` basenames are unchanged.

For this update, render with `--no-publish --reference-handoff OLD_HANDOFF`.
The exporter requires exact equality of the previous numeric snapshots and
scientific details, and pixel equality of the entire previous PNG region.
Publish the reviewed result with `--publish-handoff NEW_HANDOFF
--replace-from-handoff OLD_HANDOFF`: replacement requires each current file
to match the previous manifest, and all replaced canonical files are backed up
first. Default publication still refuses to overwrite existing files.

The titled export completed in Slurm job **13000553**. All 11 PNGs passed exact
pixel comparison with the earlier handoff in the entire original image region;
only the 200-pixel (0.5-inch at 400 dpi) title strip was added above it. Numerical
snapshots and serialized scientific details are identical across the two
handoffs. PNG/PDF/SVG canonical files and all 11 compatibility PNGs are updated.
The 33 previous canonical files are preserved in
`plots/paper_figures/posterior_appendix_e_handoff_titles_20260908_verified_previous_canonical/`.
`publication_receipt.json` records their backup and the new file hashes.

## Source mapping verified before editing

Baseline commit: `279108409a3d165ceeed430502c583f9c05e3d3b`.
The original source versions are read from this commit, not from the working
tree's newer statistical implementation. The actual export also records the
generating HEAD, working-tree diff, and source SHA-256 checksums; no new commit
is implied by a working-tree export.

| Step | Posterior source directory under `plots/` | Posterior input under `data/posterior/` | Rate source directory under `plots/` |
|---|---|---|---|
| 1 | `posterior_field_uncertainty/` | `three_set_posteriro_samples_t1_pof_cvar.jld2` | Outside this request |
| 2 | `posterior_field_uncertainty_t2_static/` | `three_set_posteriro_samples_t2_pof_cvar.jld2` | `step2_paired_posterior_stats/` |
| 3 | `posterior_field_uncertainty_t3_static/` | `three_set_posteriro_samples_t3_pof_cvar.jld2` | `step3_paired_posterior_stats/` |
| 4 | `posterior_field_uncertainty_t4_static/` | `three_set_posteriro_samples_t4_pof_cvar.jld2` | `step4_paired_posterior_stats/` |

`plot_posterior_summary_all_steps.py` explicitly supplies these four dataset
paths and directories. Slurm log `logs/out_posterior_summary_all_steps_10007316.txt`
records all eight intended `state_{mean,std}_pressurediff_pressure_sat_all_cases.png`
outputs. The static wrapper uses `--skip-videos`; `static` describes still-image
rendering, not a prior model or a different sample ensemble. The row order is
pressure difference, reservoir pressure, saturation. The pressure-first,
relative-margin, median and single-case outputs are separate figures.

All twelve `X_post1`, `X_post2`, `X_post3` arrays have h5py shape
`(128, 2, 256, 512)` = `(sample, variable, z, x)`. Variable 0 is saturation,
variable 1 is pressure. Step 2 stores float64; the original loader converts it
to float32, as it does for the other steps. This conversion is retained.
`pres_Hyd` has shape `(256, 512)`. Means and population standard deviations
(`ddof=0`) reduce sample axis 0 after the original display-unit conversion.
Pressure difference subtracts the matching `pres_Hyd`. Shared color limits
come from the original all-step script, including its fixed saturation range
0–0.9 for both mean and standard deviation. This range is preserved, despite
the low contrast it gives the saturation standard deviations.

The two pressure standard deviations are mathematically redundant: subtracting
a fixed cellwise hydrostatic field does not change variance. Small floating
point differences can remain because the original float32 computations are
retained. They must not be described as independent uncertainty findings.

## Historical statistical procedure and labels

The original generators are
`scripts/python_plots/posterior_stats/plot_step{k}_paired_posterior_stats.py`.
Inputs are the three primary paired-posterior cases in
`data/DT_control/exp_name=step{k}/case=.../sample=.../final.jld2`.
Before editing, every saved CSV endpoint and sixth rate was checked for exact
equality against these files. No sample filtering was used to force counts.

| Step | Strict PoF completed | Excluded sample IDs | Other two cases |
|---|---:|---|---:|
| 2 | 127 | 113 | 128 each |
| 3 | 124 | 11, 43, 54, 117 | 128 each |
| 4 | 122 | 5, 16, 28, 36, 47, 117 | 128 each |

Saved summaries identify these exclusions as fracture/infeasibility candidates,
with first-forward failure at the minimum rate documented for steps 3 and 4.
This is not a classification of arbitrary failed jobs as infeasible. The export
records current Slurm status separately and refuses to include active samples.

The historical procedure uses **5,000** bootstrap replicates, seed **42**,
16 histogram bins, a **1,500-point** ECDF grid, right-sided `searchsorted`,
95% pointwise percentile intervals, and the first grid value at or above 1%.
The pre-existing uncommitted changes use 10,000 replicates and direct-jump
crossings; those changes are preserved but not used for this paper handoff.

The source labels have distinct meanings, flagged before presentation edits:

- `1% q`: NumPy's interpolated sample 1% quantile. The histogram annotation
  becomes `1% quantile`; its value stays fixed. The historical shaded bootstrap
  quantile interval is omitted from the current presentation at the user's request.
- `ECDF`: first historical grid crossing of the empirical CDF at 1%.
- `q_k*`: first historical grid crossing of the upper pointwise confidence curve.
- `Opt.`: first historical grid crossing of the lower pointwise confidence curve;
  it does not denote an additional optimized schedule or recommended rate.

The three inset names remain recognizable, with mathematical typesetting for
`q_k*`. The report records all coordinates at full precision. Crossing a
discontinuous curve is **not** a guarantee that its upper bound is below 1%.
Reconciliation with Section 5.2 and the four-step simulation rates remains a
manuscript task. This export neither selects new rates nor changes schedules.

The plotted endpoint `q` is the sixth entry of the twelve-rate schedule,
computed exactly as `linspace(inj_start, raw_endpoint, 12)[5]`. The raw stored
endpoint is an affine-equivalent quantity within a case, not a second insight.

## Export and consumers

Run from the repository root:

```bash
sbatch scripts/shell/submit/submit_posterior_appendix_e_export.sh
```

The new wrapper renders only the 11 requested figures through the pinned
original plotting functions, then updates their live Matplotlib text and
layout. It creates a new handoff directory, canonical PNG/PDF/SVG files under
`plots/paper_figures/{posterior,statistical}/`, and byte-identical PNG copies
under `paper_compat/{posterior,statistical}/` inside the handoff. Existing files
are never overwritten. A repeated review run can use `--no-publish` and a new
`--handoff-dir`; this preserves the established canonical files.

To review before publishing, submit with `--no-publish`. After inspection,
`python scripts/python_plots/export_posterior_appendix_e.py --publish-handoff PATH`
checks the bundle hashes and copies the reviewed files to the canonical paths.
It does not render again. `publication_receipt.json` records the final copies.

Original entry points accept `--paper-export` plus the export options. The
posterior entry point exports all eight maps; each statistical entry point
exports its one historical grid. Without this option their existing behavior
and interfaces remain unchanged.

Updated consumers: Python/shell entry-point documentation, script index and
paper figure manifest now point to the canonical export workflow.
The Git figure allowlist admits only the new canonical posterior stems and
the three canonical statistical SVGs alongside the existing PNG/PDF rules.
Historical rate documentation, single-case figures, legacy wrappers and maintenance
scripts retain their old references because they describe historical analysis
or other outputs. No old naming convention is retired. The paper QMD is not
present in this checkout; its supplied `figs/posterior/` and `figs/statistical/`
paths remain unchanged and are served by `paper_compat/`. There are no tracked
QMD or notebook files in this repository to update. Paper-side source-asset
checksum comparison cannot be performed without that repository.

The machine-readable manifest lists every original source PNG, step, generating
script, dataset identifier, canonical path, paper path and SHA-256 checksum.
Input hashes, original-source snapshots, exact numeric plot snapshots and the
working-tree patch accompany it. Numerical validation compares all plotted
arrays, histogram rectangles, ECDF lines, confidence polygons, image limits,
colormaps, axes limits and marker coordinates before and after formatting.

## Initial completed handoff (before title restoration)

Slurm job **12992894** completed all 11 figures in 2 min 21 s, using about
5.8 GB RAM. The initial handoff is
[`plots/paper_figures/posterior_appendix_e_handoff_20260908_181644_12992894/`](../../plots/paper_figures/posterior_appendix_e_handoff_20260908_181644_12992894/).
It contains 11 PNGs at 400 dpi, 11 PDFs, 11 SVGs, 11 byte-identical manuscript-name
PNG copies, and full provenance. `manifest.json`/`manifest.csv` provide the
old/new mapping; `input_checksums.json` covers 1,171 input/source files;
`validation/scientific_details.json` records shapes, counts, bins and full-precision
marker coordinates. `publication_receipt.json` records the verified canonical
copies, made after review without rendering again.

All posterior fields, histogram counts, ECDF values, confidence polygons,
quantile intervals, axes limits and marker coordinates passed exact equality
checks before and after formatting. All original inputs and source PNGs retained
their SHA-256 checksums. The completed PNGs pass canvas-bounds and tick-overlap
checks; all SVGs contain text elements, and inspected PDFs embed TrueType fonts.

| Step | Historical strict-PoF q-star | Historical PoF 0.01 q-star | Historical CVaR q-star |
|---|---:|---:|---:|
| 2 | 0.044886855666798696 | 0.0731655070236218 | 0.11529272818953168 |
| 3 | 0.06201332035751107 | 0.08022973355342956 | 0.11865791900092487 |
| 4 | 0.07323323429161108 | 0.08114200919457668 | 0.12022143262174784 |

These are preserved historical marker coordinates, not newly selected rates.
The earlier review job 12991858 stopped at an overly strict check of unrendered
off-range ticks. Its partial handoff is retained; use only the completed
12992894 handoff above when referring to the initial title-free export. No
source plots or analysis data were removed.

## Import into the paper repository

Transfer `plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909.zip`
and its adjacent `.zip.sha256` file to the paper-repository agent. The ZIP is a
local delivery artifact; Git tracks the canonical artwork and export code.
The ZIP records the generating baseline and working-tree snapshots from
the current statistical presentation update. Keep the earlier ZIPs as previous versions.

There are 11 distinct figures: four posterior means (steps 1–4), four posterior
standard deviations (steps 1–4), and three combined histogram/ECDF figures
(steps 2–4). Each figure already contains the three risk cases. The original
request does not include a step-1 histogram/ECDF replacement. PNG/PDF/SVG formats
and the compatibility copies are representations of the same 11 figures.

For the paper intake:

1. Verify the ZIP checksum, extract it, and read `manifest.json`, `VALIDATION.md`
   and `VISUAL_REVIEW.md`. Verify the selected PNG checksums against the manifest.
2. Preserve the paper's existing 11 images in a separate backup before replacing
   them. Copy the eight PNGs from `paper_compat/posterior/` into `figs/posterior/`,
   and the three PNGs from `paper_compat/statistical/` into `figs/statistical/`,
   retaining their exact basenames. Do not bulk-copy unrelated figures.
3. Keep the active QMD image paths, Quarto IDs and existing captions. The extended
   posterior material belongs to Appendix E; pressure-bound/BHP material remains
   in Appendix D. Do not migrate statistical methods or change numerical rates.
   If a caption mentions the removed histogram quantile confidence interval,
   remove only that description; retain the ECDF confidence-interval description.
   When updating from the previous titled package, only the three statistical
   PNGs differ; the eight posterior PNGs already match byte-for-byte.
4. Render the manuscript and inspect these 11 figures at the final publication
   width. Report the replaced paths and checksum verification results, including
   any difference between the supplied mapping and the actual paper checkout.
