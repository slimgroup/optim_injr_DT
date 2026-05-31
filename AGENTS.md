# optim_injr_DT - Codex Instructions

These instructions apply to all Codex work in this repository.

## Safety and Workflow

- Do not delete or overwrite `data/`, `plots/`, `logs/`, generated `.jld2` files, SLURM outputs, or user-created scripts unless the user explicitly authorizes that exact cleanup in the current conversation.
- When adding new plots to an existing output folder, do not clear or remove pre-existing PNG/MP4/frame outputs unless the user explicitly asks for that cleanup in the current conversation.
- Treat edits to `data/three_set_posteriro_samples_t1_pof_cvar.jld2`, posterior exports, and other local analysis artifacts as destructive; ask before replacing or removing them.
- Preserve the project activation pattern in Julia entry points: keep `Pkg.activate(".")`, `using DrWatson`, and `@quickactivate "optim_injr_DT"` working unless the user explicitly asks for a workflow change.
- Preserve CLI and batch-job interfaces for `src/optim_inject.jl` and `scripts/shell/*.sh`; do not silently rename flags, change argument meanings, or break SLURM environment assumptions.
- Keep directory conventions stable: optimization outputs under `data/`, figures under `plots/`, logs under `logs/`, and reusable scripts under `scripts/`.
- For ground-truth permeability in forward-comparison figures or exports, use the 2000th element/slice from `data/geo/wise_perm_models_2000_new.jld2` unless the user explicitly asks for a different reference.
- When statistics are mathematically redundant, point that out instead of presenting them as different insights.
- Light plotting or lightweight analysis can be run on the login node when it is genuinely inexpensive, but heavy computation must go through `sbatch` or `salloc`; do not run computation-heavy jobs directly on the login node.
- Treat multi-file posterior re-rendering, bulk figure regeneration across monitoring steps, and animation generation as heavy work on PACE; run them through `sbatch` or `salloc`, not directly on the login node.
- On PACE, Codex sandboxed `sbatch`, `squeue`, and `scontrol` calls may fail with false Slurm controller connectivity errors. Before concluding that Slurm is down or that a submission script is broken, re-check those commands outside the sandbox.
- Do not rewrite git history, force push, or create commits unless the user explicitly requests it.
- At the end of a task that changes files, ask whether the user wants a git commit; if yes, use a detailed commit message that explains why and the main scope.

## Plotting Figure Layout

Apply these additional rules whenever editing plotting code, especially under `scripts/**/*.py`.

- Prefer wide, publication-style layouts with subplot proportions close to the intended final figure.
- Minimize unused whitespace, but never at the cost of overlapping titles, labels, ticks, legends, annotations, or colorbars.
- Make text as large as possible while still fitting cleanly inside the exported figure.
- Before finalizing a plot, check that titles, subtitles, tick labels, colorbar labels, and annotations do not clip or run outside the canvas.
- Keep colorbar placement visually aligned with subplot rows or columns when the figure uses repeated panels.
- Match fonts, spacing, and colorbar styling to nearby paper figures when the user asks for consistency.
- If a statistic is mathematically redundant in a figure, flag it instead of presenting it as a distinct visual insight.

## Posterior Field Plot Rules

Apply these additional rules whenever creating or updating posterior field mean / std / median figures from posterior-sample JLD2 files.

- In this repository, `relative margin` means `r = (p_max - p) / p_max` unless the user explicitly asks for a different normalization.
- For posterior-field plots, compute `p_max` consistently as `pres_Hyd + 4 MPa` for the matching monitoring step file.
- Do not silently replace the repository's `relative margin` definition with the window-normalized variant `(p_max - p) / (p_max - p0)` unless the user explicitly requests that change.
- When plotting posterior-derived `relative margin`, load the posterior pressure field itself, not `pressure_diff`, and derive the margin from that pressure field.
- When comparing posterior mean / std figures across multiple monitoring steps, keep the color scale for the same plotted variable consistent across those steps unless the user explicitly asks for step-specific rescaling.

## Statistical Analysis Plot Rules

Apply these additional rules whenever creating or updating histogram / CDF statistical analysis plots for optimized injection rates.

- In this repository, `q_k*` means the conservative value selected directly from that monitoring step's statistical analysis, i.e. the upper bootstrap CDF-band crossing at the 1% fracture-probability threshold for the plotted scalar.
- Reuse the established step-2 paired-posterior statistical plotting style unless the user explicitly asks for a different presentation.
- The default plotted scalar is the optimized injection schedule element `6/12`, reconstructed from the final nonzero endpoint in `inj_rate_arr` using the case-specific `inj_start`; do not silently switch to plotting the raw endpoint.
- For statistical analysis of optimized injection rates, explicitly treat the target scalar as the **6th element of the length-12 optimized injection rate array**. Do not silently switch to the 12th element / final element of that length-12 array.
- When documenting or updating injection-rate arrays after a monitoring step, obtain `q_k*` directly from that step's statistical analysis; do not back-solve a different quantity and relabel it as `q_k*`.
- State clearly when the endpoint is mathematically redundant with the plotted `6/12` schedule element instead of presenting both as separate insights.
- Include only completed samples with `final.jld2` in histogram / CDF summaries unless the user explicitly asks to include incomplete runs.
- Exclude currently running samples from the plotted distribution and report them separately.
- Report samples with no `final.jld2` and no active job separately as fracture / no-final candidates instead of folding them into the histogram as zeros or missing-at-random.
- Use empirical CDF with bootstrap uncertainty bands and a left-tail zoom inset when matching the established step-2 analysis.
- Keep titles explicit about monitoring step, prior mode, sample count used, and the plotted schedule element so the figure can stand alone.

## How Codex Should Behave Here

- Favor the smallest safe change that solves the task without disrupting the research workflow.
- Do not clean up generated outputs, rename interfaces, or reorganize repository structure unless the user asks.
- If a requested change risks damaging analysis artifacts, reproducibility, or batch-job workflows, stop and confirm before proceeding.

## Monitoring-Step Rules

- For the first monitoring step, the previous-state initialization is special-case logic and does not come from a previous monitoring step export; it is the randomized seeded state used to start the monitoring campaign.
- For every monitoring step after the first, recover previous-state variables from the immediately preceding monitoring step; do not silently skip backward more than one step.
- When using posterior-based priors after the first monitoring step, pair permeability sample `s` with posterior sample `s` in array order unless the user explicitly asks for a different matching rule.
- For posterior-based priors after the first monitoring step, use the previous monitoring step's posterior export as the prior-state source; do not silently reuse an older monitoring step file.
- For each risk case after the first monitoring step, `inj_start` must be shared across all samples within that case. Do not infer sample-specific `inj_start` values from previous-step per-sample optimization outputs.
- The case-level `inj_start` for monitoring step `k > 1` must come from the user-selected optimal injection-rate array of the previous monitoring step for that same case, as documented in [`docs/injection_rate_arrays.md`](docs/injection_rate_arrays.md). Use the last entry of that previous-step array as the starting rate for the new optimization campaign unless the user explicitly instructs otherwise.
- Sample-specific optimization outputs from the previous monitoring step may be used for previous-state variables, but not for choosing per-sample `inj_start`.
- When assigning posterior-based previous states into reservoir simulation inputs, keep saturation and pressure aligned to the same posterior sample and verify grid orientation before use.
