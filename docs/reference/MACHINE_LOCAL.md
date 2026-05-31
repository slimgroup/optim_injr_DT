# Machine-local directories

These folders live at the repository root but are **not** part of the shared project. They are listed in `.gitignore` and are safe to delete locally; tools will recreate them when needed.

| Directory | Purpose | Safe to delete? |
|-----------|---------|-----------------|
| `.vscode/` | VS Code / Cursor workspace settings (tasks, launch configs, extensions state) | Yes — personal preference only |
| `.mplconfig/` | Matplotlib font cache and user config (`fontlist-*.json`, etc.) | Yes — regenerated on next plot |
| `.julia_depot_cdf/` | Optional project-local depot (Cursor/experiments); **not** used by SLURM scripts | Yes — SLURM uses `~/julia-depot` instead |
| `.julia_depot_cursor/` | Optional project-local depot (Cursor/IDE sessions); **not** used by SLURM scripts | Yes — same as above |

## Julia depots (repo vs home)

**SLURM / shell entry points** set `JULIA_DEPOT_PATH="$HOME/julia-depot"` (see `scripts/shell/run/optim_inject_pace.sh`). Deleting repo `.julia_depot_*` does **not** affect batch jobs.

`run_bootstrap_cdf.sh` defaults to `$HOME/.julia` unless you override `JULIA_DEPOT_PATH`.

A project-local depot under the repo is like a mini `~/.julia`. Cursor may create `.julia_depot_cursor/` when you run Julia from the IDE.

To reclaim space:

```bash
rm -rf .julia_depot_cdf .julia_depot_cursor
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Editor settings

If you want **shared** editor rules, use the tracked `.cursor/rules/` files — not `.vscode/settings.json`.

## Related

- `.gitignore` — section “Local editor caches and machine-specific tooling”
- [DIRECTORY_STRUCTURE.md](DIRECTORY_STRUCTURE.md) — top-level layout
