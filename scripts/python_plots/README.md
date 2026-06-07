# python_plots/

Python figure assembly (paper-quality layouts).

```text
python_plots/
├── posterior_stats/   # step 2–4 paired-posterior histogram/CDF grids
├── legacy/            # older step-1 python helpers moved from julia_scripts/plotting
└── *.py               # forward comparison, perm ensemble, posterior field summaries
```

## Common entry points

| Task | Script |
|------|--------|
| Step-k paired posterior stats | `posterior_stats/plot_step{k}_paired_posterior_stats.py` |
| Posterior field mean/std (all steps) | `plot_posterior_summary_all_steps.py` |
| Forward export + 3-row figure | `../julia_scripts/data_collection/forward_exports/run_forward_export.jl` + `plot_3row_comparison.py` |
| Video from frames | `create_videos_from_frames.py` |

Shell wrapper for step-2 stats: `scripts/shell/run/run_step2_paired_posterior_stats.sh`
