# Retired quick run with gamma calibration

This filename is retained for existing references. The threshold-sensitivity
and automatic gamma-calibration workflow described here was retired with the
user's approval on 2026-10-03; its commands are no longer supported.
See [the deletion record](../reference/DELETION_REVIEW_2026-10-03.md).

The historical example used sample 128, PoF and CVaR enabled, epsilon=0.01,
unit lambda weights, alpha=0.05, five thresholds from 2 to 6 MPa, ten iterations,
and forward differences. Optional values were tau=0.05, calibration threshold
4 MPa, `inj_guess=0.05`, and `inj_start=0.0001`. The claimed 6–12× speedup was an
estimate. Calibrating gamma at a selected state does not establish equivalent
PoF/CVaR constraints for a campaign.

For current risk settings and their interpretation, use
[solver constraint handling](../optimization/SOLVER_CONSTRAINT_HANDLING.md).
For actual job commands, use [REPRODUCIBILITY.md](../REPRODUCIBILITY.md).
