# Repo Maintenance Audit - 2026-06-15

This audit records low-risk cleanup and documentation priorities for the current
repository state. It does not authorize deleting, moving, or rewriting generated
research artifacts.

## High-Priority Items

1. **Separate local research changes before committing.**
   The working tree currently contains multiple untracked forward-export,
   plotting, and submit scripts. They should be reviewed and committed by
   purpose rather than all at once.

2. **Review `plot_real_fracture_comparison_day408.py` before committing.**
   The script has local modifications and a historical filename. Verify that
   displayed rates, injected amounts, and selected input files are internally
   consistent before using or committing it.

3. **Keep paper-figure provenance explicit.**
   The paper figures combine base optimized schedules, no-control forward
   experiments, and sensitivity experiments. The file names, scripts, metadata,
   or captions should preserve which data source is used.

4. **Do not clean `plots/paper_figures/` automatically.**
   It contains both final images and large `.jld2` forward exports. Some of
   these files are expensive to regenerate, so cleanup should be explicit and
   case-by-case.

## Documentation Items

- `docs/reference/SCRIPTS_INDEX.md` should remain the canonical entry-point map
  for current scripts.
- `docs/reference/PAPER_FIGURE_MANIFEST.md` should be updated whenever a new
  paper-facing figure or video becomes part of the workflow.
- Older docs under `docs/historical/` may contain stale paths by design. Current
  workflow docs should avoid hard-coded line numbers and stale submitter names.

## Local Artifact Items

- Python `__pycache__/` directories under `scripts/` are local artifacts and
  should remain ignored. They can be removed only as a local cache cleanup.
- Root-level `logs/*.txt` files are ignored, but future jobs should prefer the
  existing `logs/optimization/`, `logs/submit/`, or `logs/utilities/`
  organization where practical.
- Shell script executable bits are inconsistent. Prefer documenting commands as
  `bash script.sh` or `sbatch script.sh` unless executable permissions are
  intentionally normalized in a separate commit.

## PACE Safety Reminders

- Heavy forward simulations, posterior rerenders, and animation generation
  should run through `sbatch` or `salloc`.
- Julia jobs should set `JULIA_DEPOT_PATH="$HOME/julia-depot"` before launching.
- Ground-truth forward-comparison figures should use the 2000th permeability
  slice from `data/geo/wise_perm_models_2000_new.jld2` unless explicitly changed.
