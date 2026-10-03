# Documentation

## Paper and reproduction

- [Reproduction guide](REPRODUCIBILITY.md): environment, data, and execution order.
- [Figure manifest](reference/PAPER_FIGURE_MANIFEST.md): selected assets and inputs.
- [Figure reading notes](figures/README.md): handoff instructions and validation summaries.
- [Injection-rate arrays](injection_rate_arrays.md): selected case-level controls.
- [Data availability](../DATA_AVAILABILITY.md): inputs and release limitations.
- [Selected posterior version](analysis/POSTERIOR_MARGIN_SELECTION_2026-10-03.md):
  the 1.13 pressure-increment sensitivity selected on October 3.
- [Posterior sensitivity method](analysis/POSTERIOR_MARGIN_SENSITIVITY_2026-10-02.md)
  and [split statistical layout](analysis/POSTERIOR_AND_STATISTICAL_LAYOUT_2026-10-02.md).

## Methods

- [Solver constraint handling](optimization/SOLVER_CONSTRAINT_HANDLING.md).
- [Optimization choices](optimization/OPTIMIZATION_CHOICE_GUIDE.md),
  [penalty weights](optimization/LAMBDA_SELECTION_GUIDE.md),
  [smoothing parameter](optimization/KAPPA_PARAMETER_EXPLANATION.md),
  [step size](optimization/STEP_SIZE_EXPLANATION.md), and
  [stopping criteria](optimization/STOPPING_CRITERIA_UPDATE.md).
- [Bootstrap CDF methodology](statistics/BOOTSTRAP_CDF_METHODOLOGY.md) and
  [CDF-grid audit](statistics/ECDF_Q_GRID_AUDIT.md).
- [Computational cost](analysis/COMPUTATIONAL_COST_BREAKDOWN.md),
  [performance](analysis/PERFORMANCE_ANALYSIS.md),
  [solver analysis](analysis/SOLVER_ANALYSIS.md), and
  [time stepping](analysis/TIME_STEPPING_ANALYSIS.md).

## Running and maintaining

- [PACE guide](workflow/PACE_RUN_GUIDE.md) and [script index](reference/SCRIPTS_INDEX.md).
- [Directory conventions](reference/DIRECTORY_STRUCTURE.md),
  [machine-local settings](reference/MACHINE_LOCAL.md), and [tests](../test/README.md).
- [Cleanup record](reference/REPOSITORY_CLEANUP.md): completed changes and
  the completed, checksum-verified artifact cleanup.
- [Approved legacy deletion](reference/DELETION_REVIEW_2026-10-03.md): exact scope and retained dependencies.

## Historical material

[Historical index](historical/README.md) holds dated presentation notes,
earlier figure revisions, KDE/gamma-table workflows, and maintenance history.
Their commands and figure choices do not override the current reproduction
guide or selected figure manifest.

Two source documents remain in `analysis/` because exporters read them directly:
[Appendix E export](analysis/POSTERIOR_APPENDIX_E_REEXPORT_2026-09-08.md) and
[the earlier margin handoff](analysis/POSTERIOR_RELATIVE_MARGIN_ACCEPTED_2026-10-02.md).
Evidence subdirectories remain at their original paths.
