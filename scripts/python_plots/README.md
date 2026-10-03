# Python plotting

The [paper manifest](../../docs/reference/PAPER_FIGURE_MANIFEST.md) records
selected outputs. Filenames such as `preview` or `presentation` are stable
interfaces; use that manifest to determine their current role.

| Task | Entry point |
|---|---|
| Selected 1.13 posterior sensitivity | `preview_posterior_margin_sensitivity.py` |
| Split step-2–4 histogram / ECDF | `restyle_paper_pngs.py` |
| New paired-posterior statistical analysis | `posterior_stats/plot_step{k}_paired_posterior_stats.py` |
| Four-step schedule | `plot_injection_schedule_over_four_steps.py` |
| Selected pressure trajectory | `plot_pressure_risk_trajectory_presentation.py` |
| Day-728 comparison | `plot_real_fracture_comparison_day408.py` |
| Joint permeability statistics | `plot_joint_permeability_statistics.py` |
| Historical Appendix E numerical export | `export_posterior_appendix_e.py` |

The historical exporter and original plotting modules are dependencies of
newer layouts. Keep their inputs and pinned source commit. Its method uses
B=5000 and the historical grid crossing; it is not a replacement for current
statistical selection. See [its source note](../../docs/analysis/POSTERIOR_APPENDIX_E_REEXPORT_2026-09-08.md).

Optional `create_*.py` scripts produce presentation videos. Bulk rendering and
animation run through Slurm. Use new output paths and PNG by default.
Dependency versions are in [requirements.txt](../../requirements.txt).
