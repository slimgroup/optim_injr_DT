# optim_injr_DT - Codex Instructions

These instructions apply to all Codex work in this repository.

## Safety and Workflow

- Do not delete or overwrite `data/`, `plots/`, `logs/`, generated `.jld2` files, SLURM outputs, or user-created scripts unless the user explicitly authorizes that exact cleanup in the current conversation.
- Treat edits to `data/three_set_posteriro_samples_t1_pof_cvar.jld2`, posterior exports, and other local analysis artifacts as destructive; ask before replacing or removing them.
- Preserve the project activation pattern in Julia entry points: keep `Pkg.activate(".")`, `using DrWatson`, and `@quickactivate "optim_injr_DT"` working unless the user explicitly asks for a workflow change.
- Preserve CLI and batch-job interfaces for `src/optim_inject.jl` and `scripts/shell/*.sh`; do not silently rename flags, change argument meanings, or break SLURM environment assumptions.
- Keep directory conventions stable: optimization outputs under `data/`, figures under `plots/`, logs under `logs/`, and reusable scripts under `scripts/`.
- When statistics are mathematically redundant, point that out instead of presenting them as different insights.
- Light plotting or lightweight analysis can be run on the login node when it is genuinely inexpensive, but heavy computation must go through `sbatch` or `salloc`; do not run computation-heavy jobs directly on the login node.
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
