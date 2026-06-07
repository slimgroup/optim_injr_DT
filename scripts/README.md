# scripts/

Operational scripts for batch jobs, plotting, and analysis. **Do not store large outputs here.**

## Layout

```text
scripts/
├── shell/                      # SLURM submit / run / check (primary entry points)
│   ├── submit/                 # sbatch wrappers
│   ├── run/                    # bash drivers
│   ├── check/                  # progress & verification
│   ├── retry/                  # reruns & queue cleanup
│   └── maintenance/            # organize_logs.py, organize_step1_data.py, …
├── julia_scripts/
│   ├── plotting/               # Julia figures/videos (posterior_stats, bootstrap_ecdf, …)
│   ├── data_collection/        # Aggregate injection-rate CSV/JLD2 exports
│   ├── analysis/               # Post-processing comparisons
│   ├── utilities/              # Diagnostics, scaling, 7-case checks
│   └── archive/                # Historical scripts (reference only)
├── python_plots/               # Python figures (posterior_stats/, paper plots, videos)
└── gamma_tables/               # Deprecated gamma-table artifacts
```

## Common entry points

| Task | Script |
|------|--------|
| Submit optimization array | `shell/run/optim_inject_pace.sh` |
| Bootstrap ECDF figures | `shell/submit/submit_bootstrap_cdf.sh` |
| Step-2 paired posterior stats | `shell/run/run_step2_paired_posterior_stats.sh` |
| Posterior field plots | `shell/submit/submit_posterior_summary_all_steps_shared.sh` |
| Video frames → MP4 | `python_plots/create_videos_from_frames.py` |
| Collect step1 inj rates | `julia_scripts/data_collection/collect_all_injection_rates.jl` |

Full index: `docs/reference/SCRIPTS_INDEX.md`

## Output conventions (after repo layout cleanup)

| Output type | Location |
|-------------|----------|
| Optimization results | `data/DT_control/exp_name=step*/` |
| Collection CSV/JLD2 | `data/.../step1/_aggregates/` |
| Bootstrap ECDF plots | `plots/DT_control/exp_name=step1/statistical_analysis/ecdf/` |
| KDE plots (legacy) | `plots/.../statistical_analysis/kde/` |
| Video runs | `plots/DT_control/videos/{5cases,128perm}/` |
| SLURM logs | `logs/` (run `shell/maintenance/organize_logs.py` to tidy) |
