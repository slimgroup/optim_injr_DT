# Data availability

Full reproduction requires simulation inputs and completed outputs that are
not distributed with the source checkout. No public data download URL or DOI
is currently specified. A release should supply a persistent data archive and
its access conditions. This list describes the existing local bundle.

## Required inputs

| Path | Role |
|---|---|
| `data/geo/wise_perm_models_2000_new.jld2` | Permeability ensemble; realization 2000 is the ground-truth reference |
| `data/state/new/Wise128_state_t{k}_rtm{k}_broad_NL_SNR28.jld2` | Monitoring-step permeability indices, k=1–4 |
| `data/posterior/three_set_posteriro_samples_t{k}_pof_cvar.jld2` | Case-specific posterior pressure/saturation, k=1–4 |
| `data/DT_control/exp_name=step{k}/` | Optimization runs; completed samples have `final.jld2` |
| `data/forward_comparisons/` | Permeability-ensemble and ground-truth forward results |

The spelling `posteriro` is part of the filename interface. Preserve sample
order, units, grid orientation, and step/case mapping when restoring inputs.
`src/optim_prior_state.jl` supports legacy locations as well; do not substitute
an older monitoring step for a missing previous-step export.

Step 1 uses a seeded randomized initial state. At step k>1, paired-posterior
runs use the k−1 export, pairing sample s with sample s. Their case-level
starting rate is the last entry of the selected k−1 injection array in
[the schedule record](docs/injection_rate_arrays.md).

## Generated and historical artifacts

- `plots/paper_figures/` contains selected PNGs **and** intermediate JLD2,
  NPZ, validation, and handoff files. Some plot scripts depend on those caches;
  removing a preview folder can remove a numerical input.
- `plots/DT_control/` and step-specific folders hold statistical exports.
- `logs/` holds Slurm output and diagnostics.
- `archive/` holds historical campaigns, including an invalid step-3 campaign
  retained for audit.

Most generated artifacts are ignored. Selected figure assets and some older
exports are already tracked. Ignore rules do not remove tracked files or erase
files from Git history. The deprecated gamma table under `scripts/gamma_tables/`
is also tracked.

## Source-only checks

Repository checks and Julia unit tests do not need the full data bundle.
Simulation integration tests, statistical reconstruction, and paper figure
reproduction do. Historical exporters also read code from commit
`279108409a3d165ceeed430502c583f9c05e3d3b`; use a full Git checkout and their
cached input bundle.

See [the reproduction guide](docs/REPRODUCIBILITY.md) and
[figure manifest](docs/reference/PAPER_FIGURE_MANIFEST.md). Run simulations,
bulk posterior rendering, and videos through `sbatch` or `salloc` on PACE.
