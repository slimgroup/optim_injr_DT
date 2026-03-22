# optim_injr_DT – Claude Code Instructions

## Safety and Workflow (always apply)

- Do not delete or overwrite `data/`, `plots/`, `logs/`, generated `.jld2` files, SLURM outputs, or user-created scripts unless the user explicitly authorizes that exact cleanup in the current conversation.
- Treat edits to `data/three_set_posteriro_samples_t1_pof_cvar.jld2`, posterior exports, and other local analysis artifacts as destructive; ask before replacing or removing them.
- Preserve the project activation pattern in Julia entry points: keep `Pkg.activate(".")`, `using DrWatson`, and `@quickactivate "optim_injr_DT"` working unless the user explicitly asks for a workflow change.
- Preserve CLI and batch-job interfaces for `src/optim_inject.jl` and `scripts/shell/*.sh`; do not silently rename flags, change argument meanings, or break SLURM environment assumptions.
- Keep directory conventions stable: optimization outputs under `data/`, figures under `plots/`, logs under `logs/`, reusable scripts under `scripts/`.
- When statistics are mathematically redundant, point that out instead of presenting them as different insights.
- Do not rewrite git history, force push, or create commits unless the user explicitly requests it.
- At the end of each task, ask whether the user wants a git commit; if yes, use a detailed commit message that explains why and the main scope.

## Plotting Figure Layout (applies when editing `scripts/**/*.py`)

- Prefer wide, publication-style layouts with subplot proportions close to the intended final figure.
- Minimize unused whitespace, but never at the cost of overlapping titles, labels, ticks, legends, or colorbars.
- Make text as large as possible while still fitting cleanly inside the exported figure.
- Before finalizing a plot, check that titles, subtitles, tick labels, colorbar labels, and annotations do not clip or run outside the canvas.
- Keep colorbar placement visually aligned with subplot rows or columns when the figure uses repeated panels.
- When changing plotting scripts, match fonts, spacing, and colorbar styling to nearby paper figures when the user asks for consistency.
- If a statistic is mathematically redundant in a figure, flag it instead of presenting it as a distinct visual insight.
