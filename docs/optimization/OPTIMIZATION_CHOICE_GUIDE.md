# Choosing hard checks and soft risk terms

Use [solver constraint handling](SOLVER_CONSTRAINT_HANDLING.md) as the detailed
implementation reference. The previous version of this guide incorrectly
suggested that hard checks disable the soft risk term and that zero-baseline
softplus is zero everywhere below the threshold.

| Intended problem | Configuration for an enabled risk metric |
|---|---|
| Maximize injection subject to the risk threshold | `--use_*`, `--*_as_constraint`, and `--lambda_* 0` |
| Trade off injection and risk, allowing threshold violations | `--use_*`, a positive lambda, and no hard flag |
| Enforce the risk threshold and favor lower risk within it | `--use_*`, `--*_as_constraint`, and a positive lambda |

Hard flags are presence-only switches: remove the flag to disable it; do not
append `false`. `--cvar_soft` controls the internal CVaR approximation, not the
presence of a risk penalty or hard check. CLI lambda defaults are zero.

For PoF, use the matching `eps_pof`; for CVaR, use the selected `alpha` and
`gamma_cvar`. Preserve `monitoring_step`, `case_key`, `prior_mode`, sample
pairing, and case-level `inj_start`. Changing constraints or weights defines a
new experiment and requires isolated outputs. The path convention does not
encode lambda, so changing only a shell `CASE_TAG` is insufficient.

The penalty is `lambda * (softplus(smoothed_risk - threshold) - softplus(0))`.
It is negative below the smoothed threshold, zero at the threshold, and positive
above it. Its gradient can remain important even when its value is small.
Hard feasibility uses the separate unsmoothed metric.

The earlier exploratory weights `1e5`, `1e6`, and `1e7`, target penalty shares
of 1–5%, and suggested 10% proximity to a threshold were heuristics, not
acceptance criteria. The established campaigns use the weights documented in
[the lambda guide](LAMBDA_SELECTION_GUIDE.md). A failed hard-constrained run can
reflect initialization or numerical problems; it does not prove the physical
constraint is impossible. Validate completed outputs and do not silently relax
risk thresholds.

The former gamma-calibration/threshold-sensitivity examples belong to the
[deprecated workflow under deletion review](../reference/DELETION_REVIEW_2026-10-03.md).
They are not a required stage of the current PoF/CVaR comparison. Run actual
optimization through Slurm using [the reproduction guide](../REPRODUCIBILITY.md).
