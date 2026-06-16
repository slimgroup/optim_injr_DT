# Data Availability

This repository intentionally does not version-control the large simulation
inputs, posterior samples, optimization outputs, logs, or generated figures used
in the paper workflow.

## Expected Local Layout

The code expects the following project-local folders when reproducing the full
research workflow:

- `data/geo/`: permeability ensembles and ground-truth permeability inputs.
- `data/posterior/`: posterior-sample JLD2 exports for each monitoring step.
- `data/state/`: digital-shadow state files and permeability-index metadata.
- `data/DT_control/`: optimization outputs, one `final.jld2` per completed case/sample.
- `plots/`: generated analysis figures, paper figures, videos, and intermediate forward exports.
- `logs/`: Slurm stdout/stderr and progress logs.

These folders are ignored by git because they are large, machine-specific, or
generated from expensive simulations.

## Reproducibility Notes

- For ground-truth forward-comparison figures, use the 2000th permeability slice
  from `data/geo/wise_perm_models_2000_new.jld2` unless a script or experiment
  explicitly documents a different reference.
- Paper-facing figure scripts are indexed in
  `docs/reference/PAPER_FIGURE_MANIFEST.md`.
- Injection schedules selected from statistical analysis are documented in
  `docs/injection_rate_arrays.md`.
- On PACE, run heavy forward simulations, posterior re-rendering, and animation
  generation through `sbatch` or `salloc`, not directly on the login node.

## Public Repository Use

The unit tests can run without the full private data bundle. Full optimization,
posterior analysis, and paper-figure reproduction require the local data bundle
described above.
