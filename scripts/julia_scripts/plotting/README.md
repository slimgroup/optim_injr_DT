# julia_scripts/plotting/

Julia figure and video scripts, grouped by workflow era.

```text
plotting/
├── posterior_stats/   # step-2 Julia paired-posterior summaries
├── bootstrap_ecdf/    # bootstrap histogram / ECDF panels (also used by run_bootstrap_cdf.sh)
├── videos/            # forward video frame generation
├── legacy_step1/      # step-1 inj-rate distributions, threshold sensitivity, 7-case plots
├── diagnostics/       # gamma-table checks, verify_* helpers (not primary entry points)
└── general/           # fracture comparison, perm ensemble, misc figures
```

Step 2–4 **Python** posterior histogram/CDF grids live under `scripts/python_plots/posterior_stats/`.

## Common entry points

| Task | Script |
|------|--------|
| Bootstrap ECDF | `bootstrap_ecdf/plot_bootstrap_panels.jl` |
| Step-2 paired posterior stats (Python) | `../python_plots/posterior_stats/plot_step2_paired_posterior_stats.py` |
| 128-perm video frames | `videos/generate_128samples_video.jl` |
| Step-1 CVaR inj-rate KDE (legacy) | `legacy_step1/plot_injr_distributions_cvar.jl` |
| POF vs CVaR threshold plot | `legacy_step1/plot_pof_vs_cvar.jl` |
