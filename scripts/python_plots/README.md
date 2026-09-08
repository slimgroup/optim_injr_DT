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
| Posterior + Appendix E paper handoff (11 figures) | `export_posterior_appendix_e.py` (Slurm wrapper below) |
| Step-k paired posterior stats | `posterior_stats/plot_step{k}_paired_posterior_stats.py` |
| Posterior field mean/std (all steps) | `plot_posterior_summary_all_steps.py` |
| Forward export + 3-row figure | `../julia_scripts/data_collection/forward_exports/run_forward_export.jl` + `plot_3row_comparison.py` |
| Four-step injection schedule | `plot_injection_schedule_over_four_steps.py` |
| Four-step pressure-risk trajectory | `plot_pressure_risk_trajectory_over_four_steps.py` |
| Real fracture comparison | `plot_real_fracture_comparison_day408.py` |
| Full-campaign fracture video | `create_full_campaign_fracture_video.py` |
| Video from frames | `create_videos_from_frames.py` |

Shell wrapper for step-2 stats: `scripts/shell/run/run_step2_paired_posterior_stats.sh`

For the historical paper re-export, use
`sbatch scripts/shell/submit/submit_posterior_appendix_e_export.sh` from the
repository root. This creates the canonical
`plots/paper_figures/posterior/posterior_{mean,std}_step{k}.png` and
`plots/paper_figures/statistical/injection_rate_hist_ecdf_step{k}.png` exports,
plus a separate handoff with manuscript-name compatibility copies. It pins
the historical 5,000-replicate, grid-crossing statistical procedure. The
figures include concise quantity/statistic titles with monitoring index `k`.
For a title-only replacement, `--reference-handoff` verifies the original
image region and numerics; `--publish-handoff ... --replace-from-handoff ...`
backs up and replaces only canonical files matching the previous manifest.
The existing posterior and step-2/3/4 entry points also accept `--paper-export`;
their default analysis behavior is unchanged. See
[the mapping and validation note](../../docs/analysis/POSTERIOR_APPENDIX_E_REEXPORT_2026-09-08.md).

For paper-ready figures, expected input data, and caveats, see
`docs/reference/PAPER_FIGURE_MANIFEST.md`.
