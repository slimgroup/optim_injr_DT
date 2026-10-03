# Recorded lambda weights

The established submission scripts use `lambda_pof=8.5e8` and
`lambda_cvar=3.0e9`. These are recorded experimental settings, not automatically
calibrated recommendations for a new objective, risk scale, or campaign.
Their ratio is about 3.53; that ratio alone does not establish that CVaR needs a
stronger penalty.

## Recorded campaigns

| Submission helper | Recorded sample coverage | Weight |
|---|---|---:|
| `submit_pof_cases_smart.sh` | 5 cases × 64 samples (65–128), 4 cases × 96 (33–128), 1 case × 128: 832 jobs | 8.5e8 |
| `submit_20_cases_samples_65_128_smart.sh` | 20 cases × 64 samples: 1,280 jobs | 3.0e9 |

The PoF cases used epsilon values 0, 0.001, 0.01, 0.02, 0.05 for the first group;
0.002, 0.003, 0.005, 0.03 for the second; and 0.1 for the third. The historical
CVaR combinations were eight with alpha=0 or 0.001 and gamma=0, 0.01, 0.02, 0.05;
three with alpha=0.01, 0.02, 0.05 and gamma=0; and nine combining those three
positive alphas with gamma=0.01, 0.02, 0.05.

## Hard checks do not disable lambda

The current objective first rejects hard-infeasible candidates, then adds the
soft risk terms for enabled metrics:

```julia
pen_pof = risk.use_pof ? risk.λ_pof *
    (softplus(pof_smooth_hat - risk.ε; κ=κ_pof) - softplus(0.0; κ=κ_pof)) : 0.0
pen_cvar = risk.use_cvar ? risk.λ_cvar *
    (softplus(cvar_smooth - risk.γ; κ=κ_cvar) - softplus(0.0; κ=κ_cvar)) : 0.0
```

The old statement that weights were merely retained as references in hard mode
was incorrect. Nonzero weights still affect feasible candidates. Set the
corresponding lambda to zero for hard-only optimization, while retaining
`use_*` and `*_as_constraint`. See
[solver constraint handling](SOLVER_CONSTRAINT_HANDLING.md) for exact modes.

Any tuning experiment needs its own output location: the existing directory
names do not encode lambda. Record objective scale, hard and smoothed risk,
weights, sample set, and solver behavior. Existing logged lambda suggestions
do not automatically change weights.

Historical submission records include `logs/submit/submit_pof_cases_simple.log`,
`submit_20_cases_65_128.log`, and `submit_20_cases_65_128_continue.log`. These local
logs are not required to be present in a public clone.
