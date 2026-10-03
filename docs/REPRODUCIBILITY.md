# Reproducing the experiments

Use a full Git checkout and record its commit, Julia manifest, Python
environment, input checksums, parameters, and selected outputs. Historical
exporters load source from a pinned Git commit, so a source ZIP alone is
insufficient for those workflows.

## 1. Environment and data

The Julia manifest records Julia 1.11.3. Follow the installation commands in
[the README](../README.md) and restore the inputs in
[data availability](../DATA_AVAILABILITY.md). Preserve `Pkg.activate(".")`,
`using DrWatson`, and `@quickactivate "optim_injr_DT"` in Julia entry points.
Run all commands from the repository root.

The plotting dependency snapshot was observed with Python 3.9.21. It is not a
full lockfile or evidence of a fresh installation test. Optional BHP audit
scripts also import `pandas`; the legacy PoF/CVaR plot imports `scipy`.
Neither optional package was present in the audited environment.

On PACE, use compute nodes for Julia installation/precompilation, optimization,
forward simulations, bulk posterior plots, and videos. Before launching Julia:

```bash
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export MPLBACKEND=Agg
```

The batch wrappers have site-specific account, module, and Python settings.
See [the PACE guide](workflow/PACE_RUN_GUIDE.md).

## 2. Four monitoring steps

The optimizer is `src/optim_inject.jl`; supporting modules are described in
[src/README.md](../src/README.md). Keep case, step, prior mode, and sample range
explicit.

- Step 1 starts with its seeded randomized state and permeability sample.
- For k>1, use the immediately previous step's posterior. Pair permeability s
  with posterior s, keeping saturation and pressure on the simulation grid.
- All samples in a case share `inj_start`, taken from the last entry of the
  selected k−1 array in [injection_rate_arrays.md](injection_rate_arrays.md).

Existing submission helpers retain their original case definitions:

```bash
mkdir -p logs
# Configured step-1 sweep; inspect the cases and array range before submission.
bash scripts/shell/submit/submit_all.sh

# Small step-3 run after step-2 inputs are available.
bash scripts/shell/submit/submit_step3_paired_smoketest.sh \
  --case pof_eps0.01 --samples 1-2

# Configured step-4 campaign after step-3 inputs and controls are available.
bash scripts/shell/submit/submit_step4_paired_all.sh --case all --samples 1-128
```

These are separate examples, not an automatic pipeline. Each later step
requires the intervening statistical selection and posterior export. These
submitters call `sbatch` internally; invoke them with `bash`. Completed runs
live under `data/DT_control/exp_name=step{k}/`.

## 3. Statistical selection

Use samples with `final.jld2`. Exclude and separately report running samples.
Samples without a final result or active job are fracture/no-final candidates,
not zero injection rates.

The scalar is element **6 of the length-12 optimized schedule**. The endpoint
is mathematically determined by that scalar and `inj_start`; it is not a second
independent statistical result. Obtain `q_k*` directly from the upper bootstrap
CDF-band crossing at the 1% threshold.

Step 1 uses `plot_bootstrap_panels.jl`; step-2–4 analysis uses the scripts in
`scripts/python_plots/posterior_stats/`. Read
[the method](statistics/BOOTSTRAP_CDF_METHODOLOGY.md) before recomputing controls.
Historical paper export retains its original grid-crossing procedure, B=5000,
and seed=42. Do not describe it as a newly computed control selection or B=10000.

## 4. Selected paper figures

Use [the figure manifest](reference/PAPER_FIGURE_MANIFEST.md). Modification
times and words such as `final` or `preview` do not establish paper selection.

Selected posterior maps use the chosen sensitivity
`p_used = pres_Hyd + 1.13 * (p - pres_Hyd)`. Relative margin is
`(p_max - p_used) / p_max`, with `p_max = pres_Hyd + 4 MPa`.
This is a sensitivity transformation, not an unmodified posterior; disclose
the factor and interpretation in the manuscript.

Reproduce into **new** directories on compute nodes:

```bash
# Requires the baseline caches described in the figure manifest.
sbatch scripts/shell/submit/submit_posterior_margin_sensitivity.sh \
  --mode increment --factor 1.13 \
  --output plots/paper_figures/NEW_posterior_margin_1p13

# Split histogram/ECDF layout with historical numerics.
sbatch scripts/shell/submit/submit_paper_png_restyle.sh \
  --output plots/paper_figures/NEW_statistical_layout
```

The manifest also identifies ground-truth realization 2000, day-728 figures,
sensitivity multipliers, and the 64/128-member joint ensemble. Preserve their
inputs and reference caches even if their folders look old. PNG is the default.

## 5. Validation and release record

Run the repository checks and relevant unit tests. Simulation validation uses
`salloc` or `sbatch`. Repository checks do not rerun the experiment or certify
every historical helper. Inspect selected local assets with:

```bash
python3 scripts/python_tools/maintenance/check_repository.py --paper-assets
```

Record the released commit/tag and supply data access information before the
paper release. See [the cleanup record](reference/REPOSITORY_CLEANUP.md) for
preserved artifacts and the completed figure cleanup. No history rewrite is
needed for this reorganization.
