# Machine-local directories

These folders live at the repository root but are **not** part of the shared project. They are listed in `.gitignore` and are safe to delete locally; tools will recreate them when needed.

| Directory | Purpose | Safe to delete? |
|-----------|---------|-----------------|
| `.vscode/` | VS Code / Cursor workspace settings (tasks, launch configs, extensions state) | Yes — personal preference only |
| `.mplconfig/` | Matplotlib font cache and user config (`fontlist-*.json`, etc.) | Yes — regenerated on next plot |
| `.julia_depot_cdf/` | Project-local Julia depot used by some CDF/bootstrap workflows | Yes — `Pkg.instantiate()` repopulates |
| `.julia_depot_cursor/` | Project-local Julia depot used by Cursor/IDE sessions | Yes — same as above |

## Julia depots

A project-local depot is like a mini `~/.julia` under the repo. It avoids polluting your global Julia environment on shared HPC systems but can grow large (packages, compiled caches, registries).

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
