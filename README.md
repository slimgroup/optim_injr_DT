# optim_injr_DT

Optimization-based injection-rate control for geological carbon storage.
Julia implements reservoir simulation and risk-constrained optimization using
probability of failure (PoF) and conditional value at risk (CVaR). Python and
Julia scripts analyze four monitoring steps and prepare the paper figures.

## Start here

- [Current figures](plots/latest/README.md): one place to browse the 21 selected
  figures without navigating dated exports and preview folders.
- [Reproduction guide](docs/REPRODUCIBILITY.md): environment, data, and execution order.
- [Paper figure manifest](docs/reference/PAPER_FIGURE_MANIFEST.md): selected figures,
  source scripts, and scientific qualifications.
- [Data availability](DATA_AVAILABILITY.md): required inputs and local outputs.
- [Injection schedules](docs/injection_rate_arrays.md): case-level controls.
- [Script index](docs/reference/SCRIPTS_INDEX.md) and [documentation index](docs/README.md).

The full experiment requires external simulation inputs and posterior exports.
A source checkout supports code inspection and data-independent unit tests;
it does not reproduce the numerical paper results without those inputs.

## Environment

Run from the repository root. `Project.toml` and `Manifest.toml` record the
Julia environment (Julia 1.11.3). [requirements.txt](requirements.txt) records
the direct plotting dependencies observed with Python 3.9.21; it is not a full
transitive lockfile. Use that Python version to match the observed environment.

```bash
git clone https://github.com/slimgroup/optim_injr_DT.git
cd optim_injr_DT
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export PYTHON="$(command -v python)"
export MPLBACKEND=Agg
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.build("PyCall")'
```

On PACE, install/precompile Julia packages and run simulations inside a compute
allocation. Batch wrappers include site-specific account, module, and Python
settings. See the [PACE guide](docs/workflow/PACE_RUN_GUIDE.md).

## Checks and execution

Lightweight repository checks do not need Julia, data, or a Slurm connection:

```bash
python3 scripts/python_tools/maintenance/check_repository.py
python3 -m unittest discover -s test/unit -p 'test_repository*.py'
```

Run the existing Julia unit suite in the configured environment:

```bash
julia --project=. test/runtests.jl
```

These tests cover helper functions and mathematical operations. They do not
validate the full simulation or establish paper-result reproducibility.
Integration tests are opt-in; see [test/README.md](test/README.md).

Submit a small paired-posterior run after restoring the required step-2 inputs:

```bash
mkdir -p logs
bash scripts/shell/submit/submit_step3_paired_smoketest.sh \
  --case pof_eps0.01 --samples 1-2
```

This command submits jobs; it is not an installation test. Read the
[reproduction guide](docs/REPRODUCIBILITY.md) before starting a campaign.

## Repository layout

| Directory | Contents |
|---|---|
| `src/` | Optimizer, risk cases, prior states, and output paths |
| `scripts/shell/` | Slurm submission, execution, and progress helpers |
| `scripts/julia_scripts/` | Forward exports, statistics, and diagnostics |
| `scripts/python_plots/` | Paper figures, posterior plots, and videos |
| `scripts/python_tools/` | Analysis and maintenance tools |
| `test/` | Lightweight checks and opt-in simulation tests |
| `docs/` | Current methods, workflow guides, and paper provenance |
| `docs/historical/` | Earlier discussions, presentations, and superseded guides |
| `data/`, `plots/`, `logs/` | Local inputs/results, figures, and job logs |
| `archive/` | Preserved historical experiments |

Historical code remains at its existing paths when batch jobs or exporters
depend on it. Use the script index to choose a current entry point. Earlier
figure exports are not interchangeable with the selected paper assets.

## Citation and license

Author: Haoyun Li. Licensed under the [MIT License](LICENSE).
Use [CITATION.cff](CITATION.cff) for the software citation and record the commit
used. Paper bibliographic details and a data DOI have not yet been provided
in this repository; add them when available.
