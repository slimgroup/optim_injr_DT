# Directory structure

| Location | Purpose and retention |
|---|---|
| Root | Project/manifest, README, license, citation, Python requirements, agent rules |
| `src/` | Core Julia code; keep CLI and project activation stable |
| `scripts/shell/{submit,run,check,retry,maintenance}/` | Stable batch and diagnostic interfaces |
| `scripts/julia_scripts/` | Julia analysis, data collection, plotting, and diagnostics |
| `scripts/python_plots/` | Paper plots, posterior statistics, and presentation videos |
| `scripts/python_tools/` | Analysis and repository checks/maintenance |
| `test/unit/` | Julia unit tests and isolated shell-submission checks |
| `test/integration/` | Opt-in simulation verification |
| `docs/analysis/` | Current selections, source documents, and retained evidence directories |
| `docs/statistics/`, `docs/optimization/` | Current method documentation |
| `docs/workflow/`, `docs/reference/` | Run guides, navigation, and figure records |
| `docs/figures/` | Figure reading notes; old export paths remain compatibility links |
| `docs/historical/` | Superseded dated notes and workflow history |
| `data/` | Inputs, posterior exports, completed optimization and forward results |
| `plots/` | Figures, videos, and some historical forward/cache inputs |
| `logs/` | Slurm stdout/stderr, submission logs, and diagnostics |
| `archive/` | Historical research campaigns and preserved log backups |

The [script index](SCRIPTS_INDEX.md) lists current entry points. The
[figure manifest](PAPER_FIGURE_MANIFEST.md) and [asset registry](paper_assets.json)
identify paper outputs; older revisions are archived or retained locally as reproduction inputs.

Directory depth matters: helpers in `scripts/shell/<group>/` resolve the
repository root with `../../..`, and submission helpers find the shared
optimization driver in `../run/`. Do not move them without updating callers.

Machine caches (`.venv/`, `__pycache__/`, `.mplconfig/`, Julia depots, editor
settings) are ignored. Retained `.cursor/` rules and agent instructions remain
in place. See [machine-local notes](MACHINE_LOCAL.md).

Do not store new generated artifacts in `scripts/` or the root. The deprecated
gamma-table workflow was removed after explicit approval; see
[the deletion record](DELETION_REVIEW_2026-10-03.md).
Do not infer that an older JLD2, cache, preview, or log is disposable: current
plot exporters can depend on it. See [data availability](../../DATA_AVAILABILITY.md)
and [the cleanup record](REPOSITORY_CLEANUP.md).
