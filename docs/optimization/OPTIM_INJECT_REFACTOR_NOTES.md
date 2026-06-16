# `optim_inject.jl` Refactor Notes

This note records a low-risk way to split `src/optim_inject.jl` into smaller units without changing the optimization behavior.

## Goal

Keep the numerical optimization flow unchanged, but move step selection, prior-state loading, and output-path assembly out of `main()` so that:

- adding `monitoring_step > 2` is easier
- adding new `case_key` values is easier
- prior-state logic is testable outside the full optimization run
- launch scripts do not need to know internal file naming rules

## Current responsibilities mixed in `optim_inject.jl`

Right now `src/optim_inject.jl` contains all of these in one file:

- CLI parsing
- case key normalization and inference
- step-specific state loading
- posterior/legacy prior-state loading
- default `inj_start` rules
- path/tag naming
- simulation/objective/gradient logic
- optimization loop
- save/plot/output handling

The refactor should split only the configuration/path logic first. Do not move the core objective/gradient loop in the first pass.

## Recommended file split

### 1. `src/optim_case_config.jl`

Move pure configuration and normalization logic here:

- `DEFAULT_INJ_START`
- `CASE_TO_POST_KEY`
- `CASE_TO_INJ_START`
- `canonical_case_key()`
- `canonical_prior_mode()`
- `infer_case_key()`
- `default_inj_start()`

This file should contain only pure functions/constants with no file I/O.

### 2. `src/optim_prior_state.jl`

Move prior-state and step-context logic here:

- `align_state_grid()`
- `slice_sample_3d()`
- `pointwise_median_3d()`
- `load_step_context()`
- `load_posterior_case_cube()`
- `load_previous_step_prior()`
- `load_posterior_prior()`
- `load_prior_state()`

This file is the right place to add future support for:

- `monitoring_step == 3`
- reading warm starts from previous optimization results
- new posterior aggregation modes like `pointwise_mean`

### 3. `src/optim_output_paths.jl`

Move naming/path helpers here:

- `scenariotag()`
- `casetag()`
- output root construction
- scratch root construction
- plot path construction

This removes string-heavy path code from `main()`.

## Suggested `main()` structure after refactor

After the split, `main()` should read like this:

1. Parse CLI args
2. Build `risk_opts`
3. Normalize `case_key` and `prior_mode`
4. Load permeability / monitoring-step context
5. Load prior state
6. Build paths and tags
7. Build simulator
8. Run first forward pass
9. Run optimization loop
10. Save final outputs

If `main()` still needs scrolling to understand the control flow, it is still too large.

## Recommended helper API

Use a small explicit API instead of many loosely coupled local variables.

### Step context

```julia
step_ctx = load_step_context(monitoring_step, s, BroadK)
```

Recommended fields:

- `step_ctx.state_data`
- `step_ctx.indices`
- `step_ctx.idx`
- `step_ctx.K`

Returning a named tuple is enough:

```julia
(state_data=state_data, indices=indices, idx=idx, K=K)
```

### Prior state

```julia
prior_ctx = load_prior_state(prior_mode, monitoring_step, case_key, s, p_max, step_ctx.K, n)
```

Recommended fields:

- `prior_ctx.sat_init`
- `prior_ctx.pres_init`
- `prior_ctx.meta`

Again, a named tuple is enough:

```julia
(sat_init=sat_init, pres_init=pres_init, meta=meta)
```

### Output paths

```julia
path_ctx = build_output_paths(risk_opts, monitoring_step, s, case_key, prior_mode)
```

Recommended fields:

- `path_ctx.run_tag`
- `path_ctx.case_tag`
- `path_ctx.exp_layer`
- `path_ctx.data_root`
- `path_ctx.out_root`
- `path_ctx.scratch_out_root`
- `path_ctx.plot_path`

## Recommended refactor order

Use this order to reduce breakage:

1. Extract constants + normalization helpers into `optim_case_config.jl`
2. Extract prior-state loaders into `optim_prior_state.jl`
3. Replace local tuple unpacking with named tuples
4. Extract path builders into `optim_output_paths.jl`
5. Only after that, shorten `main()`

Do not move the optimization loop until the configuration split is stable.

## What not to change in the first pass

Avoid these changes during the first refactor:

- changing the objective definition
- changing line-search behavior
- changing `inj_rate = collect(range(...))`
- changing save formats or key names in JLD2
- changing folder naming conventions used by existing analysis scripts

The first pass should be structure-only, not behavior-changing.

## Good next improvements after the split

Once the file is split, these improvements become easy:

- infer `inj_start` from actual previous-step result files instead of hardcoded case tables
- make `case_key` inference stricter when both PoF and CVaR are enabled
- add `pointwise_mean` as an explicit optional prior mode
- move line-search heuristics into a separate function like `initial_step_size(risk_opts, inj_start, inj_guess)`
- add unit tests for:
  - case-key normalization
  - prior cube selection
  - posterior sample pairing
  - `inj_start` defaults

## Minimal include pattern

At the top of `src/optim_inject.jl`, after `include("utils.jl")`, add:

```julia
include("optim_case_config.jl")
include("optim_prior_state.jl")
include("optim_output_paths.jl")
```

Keep the first refactor incremental. The best version is the one that preserves current experiment behavior while making the next change easier.
