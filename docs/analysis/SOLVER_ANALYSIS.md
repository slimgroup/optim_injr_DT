# Historical solver assessment

This note describes an earlier `optim_inject.jl` loop and proposed improvements.
It is not evidence that the proposals are implemented or benchmarked. Consult
the current source and [reproduction guide](../REPRODUCIBILITY.md) for actual
settings.

## Recorded implementation

The solver used projected gradient descent with finite-difference gradients,
`BackTracking(order=3, iterations=10)` from SlimOptim, and the normalized search
direction `p = -grad / gnorm`. The loop stopped at zero gradient or when:

```julia
stp < (inj_rate + [inj_start])[1] / 2 * 0.05 / 0.95
```

This is a relative step-size heuristic. The earlier wording called it a “95%
accuracy guarantee”; no proof or numerical validation of that guarantee was
provided. A small accepted step alone does not establish solution accuracy.

Finite differences require repeated forward evaluations. For `n` controls,
central differences use `2n` perturbed evaluations; forward differences use
`n` plus a baseline, which may be reusable. The implementation did not build a
Hessian approximation or reuse curvature information.

## Proposed changes, not adopted by this document

- Add objective-change and gradient-norm checks alongside the existing step
  criterion. Historical example tolerances were `1e-6`, with a minimum of three
  iterations for the objective-change check.
- Investigate L-BFGS/BFGS or nonlinear conjugate gradients if actual profiling
  shows a benefit. The suggested L-BFGS speedup of 2–5× and runtime reduction of
  30–50% were unmeasured expectations.
- Reuse the previous accepted step as the next initial line-search step; the
  recorded starting value was `ex_step_size = 0.1`.
- Consider adjoint gradients or parallel finite differences when increasing
  the number of controls. Their value must be assessed against implementation
  and validation costs for this scalar-control problem.

Example proposed convergence checks were:

```julia
rel_change = abs(obj_new - obj_old) / max(abs(obj_old), 1e-10)
if rel_change < 1e-6 && j >= 3
    break
end
if gnorm < 1e-6
    break
end
if j >= 3 && all(abs.(diff(obj_arr_niter[j-2:j+1])) .< 1e-6)
    break
end
```

These examples are retained for context. They do not authorize changes to the
scientific solver or its stopping behavior during repository maintenance.
