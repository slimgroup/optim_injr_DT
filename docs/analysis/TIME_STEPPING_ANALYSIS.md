# Historical time-discretization analysis

This note uses an earlier **80-day injection period** example. It does not
set the current campaign's period length or prove that a particular resolution
is sufficient. Verify current settings in the producing script.

## Example discretization

For `ds=10`, `forward_step=2`, and
`time_step = 80 / ds * ones(6 * ds * forward_step)`:

- Each requested time step is 8 days.
- There are 12 injection periods and 120 requested time steps.
- The forecast duration is 960 days.
- Within each period, requested output times are 8, 16, …, 80 days.

Increasing `ds` to 100 gives 0.8-day spacing and 1,200 requested time steps.
Under a constant cost per step assumption, this is approximately ten times the
work and stored states. The historical 40-minute versus 400-minute iteration
example was an estimate, not a measured scaling result. A finer time grid makes
each objective evaluation more expensive; it does not by itself increase the
number of finite-difference perturbations.

Choose a resolution by checking pressure peaks and risk metrics under
refinement, for example comparing `ds=10` and `ds=20` before a larger increase.
The earlier note assumed that ten points were sufficient without a documented
resolution study; do not use that assumption as validation.

## Scalar schedule parameterization

The recorded schedule interpolated a single endpoint:

```julia
inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
```

It is increasing when the endpoint is at least `inj_start`. There is one control
variable, so a central-difference gradient requires two perturbed forward
runs; a forward difference requires one plus the baseline.

```julia
grad[i] = (fwd - bwd) / (2 * delta_inj_rate[i])
grad[i] = (fwd - f0) / delta_inj_rate[i]
ls = BackTracking(order=3, iterations=10)
stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
inj_rate = proj(inj_rate + stp * p)
```

The projection `proj(x) = max.(x, 0)` enforces nonnegativity, not pressure-risk
feasibility. Line search and convergence still depend on the objective and
solver behavior.

An alternative with 120 independent time-step controls would require 240
central-difference perturbations or 120 forward perturbations plus a baseline.
That changes both cost and the control problem. The scalar parameterization is
therefore inexpensive to differentiate, but its restricted schedule family
must remain explicit. No solver or time-step settings were changed when this
note was translated.
