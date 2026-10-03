# Historical threshold-sweep performance estimates

This note describes the deprecated threshold-sensitivity workflow. Its timings
and speedups were planning estimates, not benchmark results. See
[the deletion review](../reference/DELETION_REVIEW_2026-10-03.md) before using its
entry points. Run simulations through Slurm, never on the login node.

## Cost model

With `ds=10` and `forward_step=2`, one objective evaluation advances
`6 * ds * forward_step = 120` requested simulation time steps. These are time
steps within a forward run, not 120 independent full simulations.

The original budget assumed 2–3 objective calls for finite differences, 3–10
for line search, and one for state update. It summarized this as roughly
5–13 calls per iteration, 100–260 per threshold at 20 iterations, and
1,000–2,600 for ten thresholds. These rough ranges were not internally exact
call counts; profile the actual implementation before allocating resources.

Assuming 0.1–1 second per time step, the original estimates were 12–120 seconds
per objective, 1–20 minutes per iteration, 20–400 minutes per threshold, and
3–67 hours for ten thresholds. Hardware, solver convergence, and rejected steps
can substantially change these estimates.

## Historical configuration options

| Change | Original expected effect | Tradeoff |
|---|---|---|
| `--niterations 5` instead of 20 | Up to 4× fewer iterations | May stop before convergence |
| `--grad_forward` | Fewer finite-difference evaluations | Different gradient accuracy |
| `--threshold_num 3` | Fewer independent thresholds | Coarser sensitivity coverage |
| `ds=5` instead of 10 | Half as many requested time steps | Requires resolution validation |
| `forward_step=1` instead of 2 | Shorter forecast horizon | Changes the optimization problem |
| Parallel threshold jobs | Potential concurrency benefit | Requires independent resources |

The historical quick, intermediate, and full settings were respectively
`(niterations, threshold_num) = (3,3), (10,5), (20,10)`; the first two used
forward differences. The proposed combined 6–12× speedup and 0.5–5 hour runtime
were unverified estimates, not validated recommendations.

Progress was inspected with `scripts/julia_scripts/utilities/check_progress.jl`
and outputs under `data/DT_control/exp_name=step1/threshold_sensitivity/`.
Current workflow instructions are in [REPRODUCIBILITY.md](../REPRODUCIBILITY.md).
