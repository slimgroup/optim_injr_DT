# Retired quick start: gamma-table PoF/CVaR comparison

The user approved retirement of this workflow on 2026-10-03. Its code, lookup
table, and old threshold-sensitivity outputs were removed; the exact inventory
is in [the deletion record](../reference/DELETION_REVIEW_2026-10-03.md).
Do not use the old submission commands from earlier Git revisions as current
paper reproduction instructions.

The historical sequence generated a gamma table for sample 128 over pressure
thresholds 2–6 MPa, checked it, ran separate PoF/CVaR threshold sweeps, and
rendered comparisons. The table used an epsilon target of 0.01. Runtime claims
of 3–5 minutes for table generation and 1–3 hours per optimization sweep were
historical estimates, not current benchmarks.

The proposed alignment and ratio interpretation did not establish a valid
general comparison of the two risk constraints. See
[the retained methodological explanation](POF_CVAR_COMPARISON_METHODS.md).
For current entry points, use [REPRODUCIBILITY.md](../REPRODUCIBILITY.md).
