# Retired PoF/CVaR comparison methods

The gamma-table comparison workflow and its old plots were removed with the
user's approval on 2026-10-03. See [the deletion record](../reference/DELETION_REVIEW_2026-10-03.md).
This note retains the methodological reason for retirement; it is not a recipe
for the current paper comparison.

The earlier proposal interpreted `CVaR / PoF > 1` as proof that CVaR was more
conservative. That interpretation is invalid: PoF measures exceedance weight,
while CVaR measures tail loss severity. Their ratio is not a general ordering
of policies or feasible sets. For relative-margin losses both can be
dimensionless, but they still represent different quantities. With an absolute
pressure loss, CVaR instead carries the loss units.

The old outputs included ratio, relative-change, min-max-normalized, and dual-axis
plots. Relative changes and normalization can describe trends within a fixed
experiment, but do not establish one method's conservatism. Dual axes retain
the original quantities while allowing arbitrary visual scale choices.

A recorded observation was that both optimized endpoints stayed near 1.05 over
a 2–6 MPa threshold sweep. Suggested explanations included weak risk weights,
solver behavior, or a bound. Those were hypotheses, not established causes;
the current endpoint optimizer has no explicit injection upper bound.

Matching a gamma value to PoF at one sampled state does not establish equivalent
constraints over all candidate schedules or geological realizations. Compare
selected policies using their actual objectives, thresholds, priors, completed
samples, and validated forward outcomes. See
[the current solver description](../optimization/SOLVER_CONSTRAINT_HANDLING.md)
and [the selected figure manifest](../reference/PAPER_FIGURE_MANIFEST.md).
