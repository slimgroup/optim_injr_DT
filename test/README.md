# Test Suite

Julia tests for `optim_injr_DT`, organized by scope.

## Layout

```text
test/
├── runtests.jl              # Main runner (includes all below)
├── unit/                    # Fast, isolated tests (no full forward sim)
│   ├── test_utils.jl
│   ├── test_risk_metrics.jl
│   ├── test_data_io.jl
│   └── test_optimization.jl
└── integration/
    └── test_ds_minimal.jl   # Forward-simulation / ds verification (heavy)
```

## Running tests

All tests:

```bash
julia --project=. test/runtests.jl
```

Unit tests only (from Julia REPL):

```julia
using Pkg; Pkg.activate(".")
include("test/unit/test_utils.jl")
include("test/unit/test_risk_metrics.jl")
include("test/unit/test_data_io.jl")
include("test/unit/test_optimization.jl")
```

Integration test on PACE (single CPU, ~minutes per `ds` value; requires `data/geo` and `data/state`):

```bash
RUN_INTEGRATION_TESTS=1 julia --project=. test/runtests.jl
# or SLURM:
sbatch scripts/shell/check/test_ds_verification.sh
bash scripts/shell/check/check_ds_verification.sh   # after job completes
```

GitHub CI runs **unit tests only** (no local geo/state data on the runner).

See also [docs/analysis/COMPUTATIONAL_COST_BREAKDOWN.md](../analysis/COMPUTATIONAL_COST_BREAKDOWN.md).

## Adding tests

1. Add `test/unit/test_<feature>.jl` or `test/integration/test_<feature>.jl`.
2. Use `@testset` blocks and `@quickactivate "optim_injr_DT"`.
3. Include the file from `runtests.jl`.
