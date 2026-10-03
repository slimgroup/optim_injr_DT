# Script entry points

Run from the repository root. Shell paths and CLI flags remain stable.
The [reproduction guide](../REPRODUCIBILITY.md) explains input dependencies;
[the figure manifest](PAPER_FIGURE_MANIFEST.md) establishes which exports are selected.

## Optimization and analysis

| Task | Entry point | Invocation |
|---|---|---|
| Core optimizer | `src/optim_inject.jl` | Julia inside a compute allocation |
| Configured step-1 case sweep | `scripts/shell/submit/submit_all.sh` | `bash` (submits jobs) |
| Step-2 comparison of median and paired priors | `scripts/shell/submit/submit_step2_dual_prior_smoketest.sh` | `bash` |
| Step-3 paired smoke test | `scripts/shell/submit/submit_step3_paired_smoketest.sh` | `bash` |
| Step-4 paired smoke test | `scripts/shell/submit/submit_step4_paired_smoketest.sh` | `bash` |
| Step-4 configured three-case campaign | `scripts/shell/submit/submit_step4_paired_all.sh` | `bash` |
| Step-1 bootstrap ECDF | `scripts/shell/submit/submit_bootstrap_cdf.sh` | `sbatch` |
| Step-2–4 paired injection-rate statistics | `scripts/python_plots/posterior_stats/plot_step{k}_paired_posterior_stats.py` | Python on a compute node |
| Collect completed injection-rate outputs | `scripts/julia_scripts/data_collection/collect_all_injection_rates.jl` | Julia on a compute node |

The low-level `scripts/shell/run/optim_inject_pace.sh` consumes the submitters'
`CASE_TAG` and `RISK_ARGS`. It is not a standalone command without that environment.

## Current paper figures

| Figure | Renderer | Batch entry / qualification |
|---|---|---|
| Selected posterior margin (factor 1.13) | `scripts/python_plots/preview_posterior_margin_sensitivity.py` | `sbatch scripts/shell/submit/submit_posterior_margin_sensitivity.sh --mode increment --factor 1.13 --output NEW_PATH` |
| Split histogram/ECDF, steps 2–4 | `scripts/python_plots/restyle_paper_pngs.py` | `sbatch scripts/shell/submit/submit_paper_png_restyle.sh --output NEW_PATH` |
| Injection schedule | `scripts/python_plots/plot_injection_schedule_over_four_steps.py` | Saved four-step controls |
| Pressure-risk trajectory | `scripts/python_plots/plot_pressure_risk_trajectory_presentation.py` | Selected presentation revision; sensitivity provenance in manifest |
| Day-728 ground-truth comparison | `scripts/python_plots/plot_real_fracture_comparison_day408.py` | Historical filename; use the exact Figure 1 command in the manifest |
| Joint permeability/pressure/saturation | `scripts/python_plots/plot_joint_permeability_statistics.py` | `scripts/shell/submit/submit_joint_permeability_statistics.sh` |
| Permeability ensemble | `scripts/python_plots/plot_perm_ensemble.py` | `scripts/shell/submit/submit_perm_ensemble_statistics.sh` |

`NEW_PATH` means a new path under `plots/paper_figures/`, not an existing output.
The selected posterior renderer retains `preview` in its filename for API stability.
Use the [asset registry](paper_assets.json) for explicit PNG paths and checksums.

## Supporting and historical workflows

- `scripts/julia_scripts/data_collection/forward_exports/`: forward simulations
  used by static figures and videos. Submit expensive runs through Slurm.
- `scripts/python_plots/create_*.py`: presentation/video workflows, indexed by
  their historical delivery notes. These are optional to static paper reproduction.
- `scripts/shell/check/`: status and diagnostic helpers.
- `scripts/shell/retry/`: targeted recovery for named historical cases.
- `scripts/julia_scripts/plotting/legacy_step1/`, `scripts/python_plots/legacy/`,
  `scripts/julia_scripts/archive/`, and `src/archive/`: retained historical code.
- `scripts/gamma_tables/`: deprecated gamma-table comparison artifact.
- `scripts/python_tools/maintenance/reorganize_*.py` and `patch_*_paths.py`:
  old one-time migrations, not routine setup steps. Do not rerun them on the
  organized repository.

Some historical-looking files are active dependencies. In particular, the
Appendix E exporter, original plotting modules, and archived source commit are
used to reproduce later layouts. Preserve them when pruning unused versions.

## Maintenance checks

```bash
python3 scripts/python_tools/maintenance/check_repository.py
python3 scripts/python_tools/maintenance/check_repository.py --paper-assets
python3 -m unittest discover -s test/unit -p 'test_repository*.py'
```

These commands do not contact Slurm or change research artifacts. The optional
asset check needs the local selected PNGs. Artifact organizers may move files;
review [the cleanup record](REPOSITORY_CLEANUP.md) before using them.
