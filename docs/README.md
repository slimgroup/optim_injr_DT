# Documentation

Project notes, workflow guides, and methodology writeups. Start here for navigation.

## Layout

```text
docs/
├── README.md
├── injection_rate_arrays.md   # canonical injection ramps (referenced from src/ and AGENTS.md)
├── workflow/                  # running and submitting jobs
├── reference/                 # repo navigation and script index
├── optimization/              # optimizer, parameters, refactor notes
├── statistics/                # bootstrap/KDE and figure methodology
├── analysis/                  # performance, solver, troubleshooting
└── historical/                # deprecated gamma-table PoF/CVaR workflow
```

## Documentation Index

### Workflow — running and submitting
- [QUICK_RUN_WITH_RISK.md](workflow/QUICK_RUN_WITH_RISK.md): short run examples with risk parameters
- [PACE_RUN_GUIDE.md](workflow/PACE_RUN_GUIDE.md): running on the PACE cluster
- [SUBMIT_GUIDE.md](workflow/SUBMIT_GUIDE.md): submission patterns and batch guidance
- [RUN_ALL_INDICES.md](workflow/RUN_ALL_INDICES.md): batch-processing walkthrough
- [MULTI_MACHINE_WORKFLOW.md](workflow/MULTI_MACHINE_WORKFLOW.md): multi-machine workflow notes
- [STEP2_LOGS_AND_PROGRESS.md](workflow/STEP2_LOGS_AND_PROGRESS.md): step-2 progress and log notes

### Reference — repository navigation
- [DIRECTORY_STRUCTURE.md](reference/DIRECTORY_STRUCTURE.md): directory layout and storage conventions
- [SCRIPTS_INDEX.md](reference/SCRIPTS_INDEX.md): entry-point map for `scripts/`
- [PAPER_FIGURE_MANIFEST.md](reference/PAPER_FIGURE_MANIFEST.md): paper figure outputs, scripts, input JLD2 files, and caveats
- [REPO_MAINTENANCE_AUDIT_2026-06-15.md](reference/REPO_MAINTENANCE_AUDIT_2026-06-15.md): current repo audit and safe cleanup priorities
- [../DATA_AVAILABILITY.md](../DATA_AVAILABILITY.md): required local data bundle and generated artifacts
- [MACHINE_LOCAL.md](reference/MACHINE_LOCAL.md): `.vscode`, `.mplconfig`, `.julia_depot_*` (not in git)
- [SCRIPT_EXPLANATION.md](reference/SCRIPT_EXPLANATION.md): detailed SLURM script pattern notes

### Optimization — methods and parameters
- [OPTIMIZATION_CHOICE_GUIDE.md](optimization/OPTIMIZATION_CHOICE_GUIDE.md): optimizer selection and hard vs soft constraints
- [OPTIM_INJECT_REFACTOR_NOTES.md](optimization/OPTIM_INJECT_REFACTOR_NOTES.md): `optim_inject.jl` refactor plan
- [KAPPA_PARAMETER_EXPLANATION.md](optimization/KAPPA_PARAMETER_EXPLANATION.md): kappa parameter explanation
- [LAMBDA_SELECTION_GUIDE.md](optimization/LAMBDA_SELECTION_GUIDE.md): lambda-weight guidance
- [STEP_SIZE_EXPLANATION.md](optimization/STEP_SIZE_EXPLANATION.md): step-size notes
- [STOPPING_CRITERIA_UPDATE.md](optimization/STOPPING_CRITERIA_UPDATE.md): stopping-criterion updates
- [CONTROL_THEORY_ANALYSIS.md](optimization/CONTROL_THEORY_ANALYSIS.md): control-theory interpretation

### Statistics and plotting
- [BOOTSTRAP_CDF_METHODOLOGY.md](statistics/BOOTSTRAP_CDF_METHODOLOGY.md): bootstrap CDF methodology
- [KDE_CI_METHODOLOGY.md](statistics/KDE_CI_METHODOLOGY.md): KDE and confidence-interval notes
- [injection_rate_arrays.md](injection_rate_arrays.md): documented injection-rate ramps and indexing
- [PLOT_LAYOUT_DISCUSSION.md](statistics/PLOT_LAYOUT_DISCUSSION.md): figure-layout notes

### Analysis — performance and troubleshooting
- [PERFORMANCE_ANALYSIS.md](analysis/PERFORMANCE_ANALYSIS.md): performance notes
- [COMPUTATIONAL_COST_BREAKDOWN.md](analysis/COMPUTATIONAL_COST_BREAKDOWN.md): cost breakdown
- [SOLVER_ANALYSIS.md](analysis/SOLVER_ANALYSIS.md): solver analysis
- [TIME_STEPPING_ANALYSIS.md](analysis/TIME_STEPPING_ANALYSIS.md): time-stepping notes
- [MISSING_SAMPLES_ANALYSIS.md](analysis/MISSING_SAMPLES_ANALYSIS.md): missing-sample investigation

### Historical — deprecated workflows
- [QUICK_START.md](historical/QUICK_START.md): gamma-table quick start (deprecated)
- [POF_CVAR_COMPARISON_METHODS.md](historical/POF_CVAR_COMPARISON_METHODS.md): PoF/CVaR comparison methods (deprecated)

Gamma-table material under `scripts/gamma_tables/` is retained for reproducibility only.

## Quick Links

- [../README.md](../README.md): project overview
- [../test/README.md](../test/README.md): test guide
- [../logs/README.md](../logs/README.md): SLURM log layout

## Suggested Reading Paths

### New to the repo
1. [QUICK_RUN_WITH_RISK.md](workflow/QUICK_RUN_WITH_RISK.md)
2. [DIRECTORY_STRUCTURE.md](reference/DIRECTORY_STRUCTURE.md)
3. [SCRIPTS_INDEX.md](reference/SCRIPTS_INDEX.md)

### Running jobs on PACE
- [PACE_RUN_GUIDE.md](workflow/PACE_RUN_GUIDE.md)
- [SUBMIT_GUIDE.md](workflow/SUBMIT_GUIDE.md)
- [SCRIPTS_INDEX.md](reference/SCRIPTS_INDEX.md)

### Working on paper figures
- [injection_rate_arrays.md](injection_rate_arrays.md)
- [PAPER_FIGURE_MANIFEST.md](reference/PAPER_FIGURE_MANIFEST.md)
- [BOOTSTRAP_CDF_METHODOLOGY.md](statistics/BOOTSTRAP_CDF_METHODOLOGY.md)
- [PLOT_LAYOUT_DISCUSSION.md](statistics/PLOT_LAYOUT_DISCUSSION.md)
