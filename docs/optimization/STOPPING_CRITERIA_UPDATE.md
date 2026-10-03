# Historical stopping-criteria proposal

This note records proposed extra stopping checks. In the current
`src/optim_inject.jl`, the small-gradient and relative-objective-change checks
are commented out. Their presence in this note does not mean they are active.
See [the current solver description](SOLVER_CONSTRAINT_HANDLING.md).

The proposal checked `gnorm < 1e-5` from iteration 2, and two consecutive relative
objective changes below `1e-6` from iteration 3:

```julia
if j >= 2 && gnorm < 1e-5
    break
end
if j >= 3
    obj_prev = obj_arr_niter[j]
    obj_prev2 = obj_arr_niter[j-1]
    rel_change = abs(obj - obj_prev) / max(abs(obj_prev), 1e-10)
    rel_change_2 = abs(obj_prev - obj_prev2) / max(abs(obj_prev2), 1e-10)
    if rel_change < 1e-6 && rel_change_2 < 1e-6
        break
    end
end
```

The existing loop retains the zero-gradient check and relative step criterion:

```julia
if gnorm == 0.0
    break
end
if stp < (inj_rate + [inj_start])[1] / 2 * 0.05 / 0.95
    break
end
```

The historical description of this step criterion as a “95% accuracy guarantee”
was unsupported. None of these checks proves global optimality or a probability
of correctness. The recorded expectation of stopping after 5–7 iterations,
saving 3–5 iterations or 20–30% runtime, was a forecast, not a benchmark.
The original observation concerned ten jobs at iteration 5 with approximately
40 minutes per iteration; it is not current job status.

L-BFGS and adjoint gradients were suggested for future investigation. No solver
behavior or numerical stopping criteria were changed during documentation
cleanup.
