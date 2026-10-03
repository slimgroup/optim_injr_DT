# Kappa and the softplus penalty

For the current implementation and its limitations, see
[solver constraint handling](SOLVER_CONSTRAINT_HANDLING.md). This guide replaces
older claims of a fixed “99% hardness” or guaranteed constraint accuracy.

## Formula and implementation

The usual softplus and its derivative are

```text
s_kappa(x) = log(1 + exp(kappa*x)) / kappa
s_kappa'(x) = sigmoid(kappa*x)
```

`src/optim_inject.jl` evaluates the following clamped version:

```julia
function softplus(x; κ::Float64 = 50.0)
    y = κ * x
    y = clamp(y, -50.0, 50.0)
    return log1p(exp(y)) / κ
end
```

The standard derivative formula applies inside the unclamped interval. The
implemented function saturates outside it; do not extrapolate the usual
large-positive-input linear asymptote to the clamped implementation.

Larger positive kappa sharpens the transition near zero; smaller kappa broadens
it. Approximation error depends on both kappa and the input scale. Kappa is not
a probability, a constraint tolerance, or an accuracy percentage. The CLI
values `--kappa_pof` and `--kappa_cvar` default to 50.0.

## Zero-baseline risk terms

```text
PoF term  = lambda_pof  * (s_kappa_pof(P_smooth - epsilon) - s_kappa_pof(0))
CVaR term = lambda_cvar * (s_kappa_cvar(C_smooth - gamma) - s_kappa_cvar(0))
```

The subtraction makes the term zero at the smoothed risk threshold. It is
negative below the threshold and positive above it, rather than zero throughout
the feasible region. For kappa=50, the unweighted values at violations -0.01,
0, and +0.01 are approximately -0.0043814, 0, and +0.0056186. The subtraction is
a constant shift; it does not change the gradient.

`--cvar_soft` also uses `kappa_cvar` for the internal RU hinge approximation.
Hard PoF/CVaR checks use their separate unsmoothed metrics. Increasing kappa
cannot substitute for enabling or validating a hard constraint.

## Exploring settings

The historical guide considered 20–40 for a broader transition and 70–100 for
a sharper transition. These are exploratory values, not validated defaults for
new experiments. Inspect feasibility, gradients, accepted steps, and the risk
terms; a small penalty value alone does not imply a small gradient contribution.

The optional `--plot_softplus_demo --kappa_pof 50 --kappa_cvar 50` flags generate
`softplus_demo.png` through the existing entry point. Follow the established
Slurm workflow for any entry point that also runs simulation.

Related guides: [lambda weights](LAMBDA_SELECTION_GUIDE.md),
[constraint modes](OPTIMIZATION_CHOICE_GUIDE.md), and
[time steps versus optimization steps](STEP_SIZE_EXPLANATION.md).
