# Test Suite

This directory contains the test suite for the `optim_injr_DT` project.

## Running Tests

To run all tests, use:

```julia
julia --project=. test/runtests.jl
```

Or from the Julia REPL:

```julia
using Pkg
Pkg.activate(".")
include("test/runtests.jl")
```

## Test Files

- `test_utils.jl` - Tests for utility functions (softplus, basic math operations, array operations)
- `test_risk_metrics.jl` - Tests for risk metric computations (POF, CVaR, weights)
- `test_data_io.jl` - Tests for data I/O operations (file paths, JLD2 operations)
- `test_optimization.jl` - Tests for optimization-related functions (gradients, projections, line search)

## Test Structure

Each test file contains multiple `@testset` blocks that group related tests together. The main test runner (`runtests.jl`) includes all test files and reports the results.

## Adding New Tests

To add new tests:

1. Create a new test file in the `test/` directory (e.g., `test_new_feature.jl`)
2. Follow the existing pattern with `@testset` blocks
3. Include the new test file in `runtests.jl`

Example test structure:

```julia
using DrWatson, Test
@quickactivate "optim_injr_DT"

@testset "New Feature Tests" begin
    @test 1 + 1 == 2
    # Add more tests here
end
```

