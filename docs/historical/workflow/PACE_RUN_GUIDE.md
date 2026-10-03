# Retired PACE guide: gamma-table threshold comparison

This historical workflow was removed with explicit user approval on 2026-10-03.
The [deletion inventory](../../reference/DELETION_REVIEW_2026-10-03.md) identifies
the retired implementations, wrappers, table, plotters, and outputs. Use the
[current PACE guide](../../workflow/PACE_RUN_GUIDE.md) for supported workflows.

The old method used bisection to find an injection endpoint with PoF near a
target epsilon, then recorded its CVaR as gamma for each pressure threshold.
The sample-128 table covered 2, 3, 4, 5, and 6 MPa with epsilon=0.01. Separate
PoF-only and CVaR-only sweeps typically used ten iterations and unit penalty
weights. Environment overrides included `EPS_POF`, `GAMMA_TABLE_PATH`,
`LAMBDA_POF`, `LAMBDA_CVAR`, and `THRESHOLD_VALUES`.

The earlier guide reported inaccurate table entries and recommended
regeneration. Its timing estimates ranged from 3–5 to 15–25 minutes for table
generation, and its claim that CVaR should necessarily yield a lower injection
rate was not a validated conclusion. Calibration at one operating state does
not establish globally equivalent risk constraints. The
[comparison-method note](../POF_CVAR_COMPARISON_METHODS.md) explains why the
workflow should not be restored as the paper's default comparison.
