# Simulation time steps and optimization steps

These are different parameters in `src/optim_inject.jl`.

| Quantity | Parameters | Meaning |
|---|---|---|
| Simulation time step | `ds`, `dt_firstblock` | Requested temporal resolution of the reservoir simulation |
| Optimization step | `ex_step_size`, accepted `stp` | Distance along the projected search direction in the endpoint control variable |

The historical example `dt_firstblock = 80/ds` gives ten 8-day steps when
`ds=10`, or one 80-day step when `ds=1`. Both cover an 80-day block. This does not
establish equal runtime or accuracy; nonlinear solver convergence and internal
step handling matter. The earlier “18% runtime difference” was a particular
reported observation, not a general scaling rule.

The recorded backtracking setup is `BackTracking(order=3, iterations=15)`.
Its initial trial step is 0.15 for PoF hard-constraint cases and 0.2 otherwise.
Subsequent searches reuse the previous accepted step. The update is
`inj_rate = proj(inj_rate + stp * p)`.

The parameters have separate meanings, but changing simulation resolution can
change objective values, gradients, and hence optimization behavior. Consult
[solver constraint handling](SOLVER_CONSTRAINT_HANDLING.md) before interpreting
convergence or modifying either setting.
