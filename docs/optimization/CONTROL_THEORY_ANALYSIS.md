# Control architecture: historical design discussion

This note originally assessed one optimization window. Its conclusion that the
whole project lacked feedback does not describe the later monitoring campaign,
which updates priors and previous states between monitoring steps. Distinguish
the open-loop solve inside a window from the outer monitoring/update loop.

## One-window parameterization

```julia
inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
```

This constructs a linear schedule from a fixed starting rate and one optimized
endpoint. The length alone does not establish a receding-horizon controller.
A feedback controller also needs state updates and repeated optimization after
applying part of a schedule. The campaign's actual state-transfer rules are in
[AGENTS.md](../../AGENTS.md) and [the run order](../REPRODUCIBILITY.md).

## Concepts considered

| Concept | Role in the historical discussion |
|---|---|
| Model predictive control (MPC) | Optimize a horizon, apply the next control block, update the state, repeat |
| Prediction horizon | Future interval represented in the optimization |
| Control horizon | Interval or number of independent control decisions |
| Feedforward planning | Compute a schedule from the available initial state |
| Feedback | Update decisions using new state information |
| Hard constraints | Reject candidates violating the selected risk criterion |
| Soft penalties | Trade off injection benefit and risk in the objective |
| Terminal cost/constraints | Proposed tools requiring a separate stability analysis |
| Robust MPC | Proposed scenario, min-max, or tube approaches to uncertainty |
| Economic MPC | Directly optimize injection benefit rather than track a fixed target |

A conceptual feedback loop is:

```text
measure/estimate state -> optimize future controls -> apply next block
                      -> update state -> repeat
```

The earlier suggested example used a prediction horizon of 12 and control
horizon of 6. These were design examples, not validated new campaign settings.
Optimizing scenarios independently is also not by itself a shared robust MPC
policy.

## Proposed alternatives

The discussion considered staged optimization, piecewise-linear/polynomial/
spline schedules, explicit ramp constraints, and an offline reference schedule
followed by online tracking. Example extensions included:

```text
u(t) = a + b*t + c*t^2
abs(u(t+1) - u(t)) <= delta_u_max
u(t) = u_max * sigmoid((t - t_mid) / tau)
```

An example smoothing cost was
`lambda_smooth * sum((u[i+1] - u[i])^2 for i in 1:length(u)-1)`.
These proposals are not changes to the current solver. Linear interpolation
restricts the schedule shape but does not impose an independently specified
ramp-rate bound. Terminal conditions and feedback do not alone prove stability.

## References retained from the original note

- Rawlings, J. B., and Mayne, D. Q. (2009), *Model Predictive Control: Theory and Design*.
- Camacho, E. F., and Bordons, C. (2013), *Model Predictive Control*.
- Grüne, L., and Pannek, J. (2017), *Nonlinear Model Predictive Control*.

Bibliographic details and applicability were not revalidated during translation.
