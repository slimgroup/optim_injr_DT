# Solver constraint handling: soft penalties and hard checks

Source review date: 2026-10-02. This document describes `src/optim_inject.jl` and
the submission scripts. No optimization was rerun and no solver behavior was
changed during the review or English-language revision.

The solver uses finite-difference gradient descent, nonnegative projection, and
backtracking line search. Hard checks determine candidate feasibility; soft
risk terms trade off injection benefit against risk among finite candidates.
The established PoF/CVaR submissions enable both.

| Mechanism | Implementation |
|---|---|
| Hard constraint | Return `Inf` when an unsmoothed risk metric exceeds its threshold |
| Soft penalty | Add a weighted, smoothed risk term to the objective |
| `--cvar_soft` | Smooth the internal CVaR calculation used by the penalty; retain the separate hard check |
| `proj(x) = max.(x, 0)` | Project the injection endpoint onto nonnegative values |

## 1. Control variable and injection objective

The optimized variable is one endpoint, $q$. With fixed `inj_start`, the
length-12 schedule is

$$
q_i(q)=q_{\mathrm{start}}+\frac{i-1}{11}(q-q_{\mathrm{start}}),
\qquad i=1,\ldots,12.
$$

These are not 12 independent controls. Each candidate generates the full
schedule and runs a forward simulation. The reviewed configuration uses
80-day blocks with ten requested outputs per block: 120 forecast outputs over
960 days. Verify the producing configuration when comparing other workflows.

The base objective is negative injected CO₂ mass:

$$
J_{\mathrm{base}}(q)=-M_{\mathrm{CO_2}}(q).
$$

The scalar used in the injection-rate statistics is
$q_6=q_{\mathrm{start}}+5(q-q_{\mathrm{start}})/11$. For fixed `inj_start`, this
and the endpoint are one-to-one transformations, not independent insights.
The endpoint must not be labeled as the sixth element.

Sources: [schedule and objective](../../src/optim_inject.jl#L448),
[forecast settings](../../src/optim_inject.jl#L671).

## 2. Pressure-derived risk

The pressure bound and relative margin are

$$
p_{\max}(x)=p_{\mathrm{hyd}}(x)+4\,\mathrm{MPa},\qquad
r(x,t)=\frac{p_{\max}(x)-p(x,t)}{p_{\max}(x)}.
$$

Positive, zero, and negative margins indicate pressure below, at, and above the
bound, respectively. `--risk_mode relative` selects this normalization.
`--weight_mode voltime` weights cells and forecast times by volume and duration,
normalized to $\sum_iw_i=1$. Here $i$ indexes space-time combinations.

The PoF/CVaR within one optimization is a space-time statistic for the current
geological realization. It is not directly a fracture probability across
posterior samples. The later optimized-rate CDF/bootstrap analysis is a
separate statistical layer; its probability threshold is not interchangeable
with solver `eps_pof` or `alpha`.

Sources: [pressure bound](../../src/optim_inject.jl#L636),
[distribution and weights](../../src/optim_inject.jl#L295).

## 3. PoF: separate hard and smoothed metrics

$$
P_{\mathrm{hard}}(q)=\sum_iw_i\mathbf{1}[r_i(q)<0],
\qquad
P_{\mathrm{smooth}}(q)=\sum_iw_i\sigma\!\left(-\frac{r_i(q)}{\tau}\right),
\quad \sigma(z)=\frac{1}{1+e^{-z}}.
$$

`pof_hard_hat` is compared with `eps_pof`; `pof_smooth_hat` enters the penalty.
`tau_pof` controls the sigmoid transition width. At exactly zero margin, the
strict hard indicator is zero while the smooth indicator is 0.5. Consequently,
a hard-feasible candidate may still have a positive PoF penalty.

Source: [PoF metrics](../../src/optim_inject.jl#L344).

## 4. CVaR: severity in the worst tail

CVaR uses nonnegative excess-pressure loss:

$$
L_i=\max(0,-r_i)=\max\!\left(0,\frac{p_i-p_{\max,i}}{p_{\max,i}}\right).
$$

`alpha` is the worst-tail weight fraction. `alpha=0.01` means the worst 1%, not
a 1% confidence level. `cvar_eval` sorts losses in descending order and averages
exactly alpha weight, using fractional boundary weight if needed. It supplies
the hard check and recorded CVaR metric. `cvar_smooth` uses the RU form for the
penalty:

$$
C_\alpha(L)=\min_\eta\left[\eta+\frac{1}{\alpha}
\sum_iw_i\max(0,L_i-\eta)\right].
$$

`--cvar_soft` replaces the internal hinge by softplus. Regardless of that flag,
the hard check uses `cvar_eval` from `cvar_clean`.

Thus `--alpha 0.01 --gamma_cvar 0.1` limits the average relative excess pressure
in the worst 1% of space-time weight to 0.1. The value 0.1 is a severity bound,
not a fracture probability or a pointwise bound on every cell.
Both CVaR implementations clamp alpha to $[10^{-6},0.9999]$; `--alpha 0`
therefore requests an effective $10^{-6}$ tail, not an explicit maximum-loss
calculation.

Sources: [tail and RU calculations](../../src/optim_inject.jl#L361),
[loss construction](../../src/optim_inject.jl#L530).

## 5. Combined objective

The hard checks have the form

```julia
if use_pof && pof_as_constraint && pof_hard > ε + 1e-12
    return Inf
end
if use_cvar && cvar_as_constraint && cvar_eval > γ + 1e-12
    return Inf
end
```

After these checks, the enabled penalties are added. Within the unclamped
softplus interval, define $s_\kappa(z)=\log(1+e^{\kappa z})/\kappa$. Then

$$
B_{\mathrm{PoF}}=\lambda_{\mathrm{PoF}}
[s_{\kappa_{\mathrm{PoF}}}(P_{\mathrm{smooth}}-\varepsilon)
-s_{\kappa_{\mathrm{PoF}}}(0)],
$$

$$
B_{\mathrm{CVaR}}=\lambda_{\mathrm{CVaR}}
[s_{\kappa_{\mathrm{CVaR}}}(C_{\mathrm{smooth}}-\gamma)
-s_{\kappa_{\mathrm{CVaR}}}(0)].
$$

$$
J(q)=\begin{cases}
+\infty,&\text{an enabled hard check fails},\\
-M_{\mathrm{CO_2}}(q)+B_{\mathrm{PoF}}(q)+B_{\mathrm{CVaR}}(q),
&\text{the hard checks pass}.
\end{cases}
$$

Simulation failures may also return `Inf`; that value alone does not prove a
risk violation. Hard checks restrict the acceptable set, while nonzero lambda
still changes objective ordering within it. Weights remain fixed during a run;
logged lambda suggestions do not update them.

A hard PoF threshold of 0.01 allows approximately 1% weighted space-time
exceedance. “Hard” does not mean no cell may exceed the bound. A zero threshold
is stricter, but remains subject to discrete output times and numerical
tolerance.

Sources: [objective checks and penalties](../../src/optim_inject.jl#L535),
[lambda diagnostics](../../src/optim_inject.jl#L779).

## 6. Meaning of zero baseline

The penalty is zero when the **smoothed metric equals its threshold**. It is
negative below the threshold, not identically zero throughout the feasible
region. With $z=\text{smoothed metric}-\text{threshold}$:

| $z$ | $s_{50}(z)-s_{50}(0)$ before multiplying by lambda |
|---:|---:|
| -0.01 | -0.0043814 |
| 0 | 0 |
| +0.01 | +0.0056186 |

Subtracting $s_\kappa(0)$ is a constant shift, so it does not change gradients
or minimizers. Within the unclamped interval,
$dB/dz=\lambda\sigma(\kappa z)$, giving slope $\lambda/2$ at the threshold.
A zero or small penalty value does not imply a small gradient contribution.

The implementation clamps `kappa*x` to [-50,50] before exponentiation. It
saturates for large positive inputs; the standard softplus linear asymptote
does not apply there. Source: [softplus](../../src/optim_inject.jl#L196).

## 7. Switch combinations and established settings

The following table applies separately to PoF and CVaR.

| `use_*` | `*_as_constraint` | `lambda_*` | Treatment |
|---|---|---:|---|
| Off | Either | Any | No objective contribution or hard check |
| On | Off | >0 | Soft risk term only |
| On | On | 0 | Hard check only |
| On | On | >0 | Hard check and soft term |
| On | Off | 0 | No restriction from this metric |

`--cvar_soft` only controls internal CVaR smoothing; switching it off does not
remove the outer softplus penalty. CLI lambda defaults are zero.
The established step-4 risk argument fragments are:

```text
PoF:
--use_pof --pof_as_constraint
--lambda_pof 8.5e8 --tau_pof 0.05 --kappa_pof 50
--eps_pof 0.0 or 0.01
--risk_mode relative --weight_mode voltime

CVaR:
--use_cvar --cvar_as_constraint --cvar_soft
--lambda_cvar 3.0e9 --kappa_cvar 50
--gamma_cvar 0.1 --alpha 0.01
--risk_mode relative --weight_mode voltime
```

These enable both hard and soft handling. `HARD` in a directory name records
the hard flag; `cvarsoft` records internal smoothing. Their coexistence is
intentional.

| Parameter | Meaning |
|---|---|
| `eps_pof` | Hard PoF threshold and smoothed-penalty reference |
| `gamma_cvar` | Hard CVaR threshold and smoothed-penalty reference |
| `alpha` | Worst-tail weight fraction |
| `tau_pof` | PoF indicator smoothing width |
| `kappa_pof` | Outer PoF penalty sharpness |
| `kappa_cvar` | Outer CVaR penalty and optional internal RU smoothing sharpness |
| `lambda_*` | Risk weight relative to injection benefit |

Sources: [step-4 submissions](../../scripts/shell/submit/submit_step4_paired_all.sh#L39),
[case options](../../src/optim_case_config.jl#L120),
[output naming](../../src/optim_output_paths.jl#L5).

## 8. One optimization update

1. Find a finite initial objective. If necessary, multiply the endpoint by 0.8
   repeatedly; failure at endpoint 0.0001 raises an error. Fixed `inj_start`
   does not shrink, so the full schedule is not scaled uniformly.
2. Compute finite differences with perturbation $\delta=10^{-8}$. Central
   differences are the CLI default; established batch scripts request
   `--grad_forward`. Both evaluate the full objective, including hard checks.
3. Use $d=-g/\lVert g\rVert_\infty$. A finite nonzero scalar gradient gives
   direction +1 or -1.
4. Form $q_{\mathrm{trial}}=\max(0,q+a d)$. There is no imposed upper bound;
   `inj_guess` is an initial guess, not a cap.
5. In normal backtracking, first shrink nonfinite trials to find a finite
   objective, then check sufficient decrease and shrink again if needed.
6. Record the accepted update and risks, recompute the gradient, and check
   iteration limits, zero gradient, the small-step criterion, or failure paths.

$$
g_{\mathrm{central}}\approx\frac{J(q+\delta)-J(q-\delta)}{2\delta},
\qquad g_{\mathrm{forward}}\approx\frac{J(q+\delta)-J(q)}{\delta}.
$$

Normal line search uses the Armijo condition

$$
J(q_{\mathrm{trial}})\leq J(q)+c_1a\,g^{\mathsf T}d,
\qquad c_1=10^{-4}.
$$

The loop uses `BackTracking(order=3, iterations=15)`, initially trying 0.15 for
PoF hard cases and typically 0.2 otherwise. Later searches start from the last
accepted step. The 15-iteration limit applies to sufficient-decrease
backtracking; the dependency has a separate initial finite-value search.
For example, an endpoint trial from 0.05 to 0.07 may fail the hard check.
A smaller trial at 0.06 must still satisfy sufficient decrease after balancing
injection benefit and the soft risk term.

Sources: [initial feasibility](../../src/optim_inject.jl#L732),
[finite differences](../../src/optim_inject.jl#L576),
[main loop](../../src/optim_inject.jl#L860),
[batch settings](../../scripts/shell/run/optim_inject_pace.sh#L55).
The original review also checked the local Manifest-matched
`LineSearches 7.4.1/src/backtracking.jl` implementation.

## 9. Numerical and interpretive limits

- A feasible point can have an infeasible finite-difference perturbation,
  producing an infinite gradient and potentially a NaN normalized direction.
  There is no dedicated feasible-side or adaptive-perturbation fallback.
- The line-search exception handler tries a fixed step of 0.001 and checks only
  finiteness. Therefore not every accepted fallback step is guaranteed to
  satisfy Armijo decrease or monotonic objective reduction.
- `cvar_soft` does not make the whole objective globally smooth: the loss hinge,
  all-zero-loss special case, clamp, and hard `Inf` boundary remain.
- The active rule $a<[(q+q_{\mathrm{start}})/2](0.05/0.95)$ is a stopping
  heuristic, not a proof of “95% accuracy.” Supplementary small-gradient and
  objective-change checks are commented out in the reviewed current code.
- `BHP_max` is recorded and plotted but does not enter these PoF/CVaR feasibility
  checks. They use reservoir pressure risk.
- Hard checks cover the simulated, discretized risk metric, not every point in
  continuous space-time, every posterior realization, or unconditional field
  safety. The solver provides no global optimality guarantee.

Sources: [exception fallback](../../src/optim_inject.jl#L887),
[stopping rule](../../src/optim_inject.jl#L1013),
[BHP use](../../src/optim_inject.jl#L689).

## 10. Interpreting saved fields

| Field | Interpretation |
|---|---|
| `pof_hard_iter` | Unsmoothed PoF; compare with epsilon + 1e-12 when hard PoF is enabled |
| `pof_iter` | Smoothed PoF used by the penalty, not a substitute for the hard metric |
| `cvar_iter` | Strict-tail `cvar_eval`; compare with gamma + 1e-12 when hard CVaR is enabled |
| `pen_pof_arr`, `pen_cvar_arr` | Signed penalty histories; negative values are possible |
| `obj_base_arr` | Negative injected mass; more negative means more mass |
| `obj_arr_niter` | Total objective including risk terms, not injected mass alone |
| `meta.risk_opts` | Actual flags, thresholds, weights, and smoothing settings |

Use only completed iterations: preallocated tails may remain zero or NaN after
early stopping. Logged penalty shares divide by the signed total objective;
the penalty-share plot divides by the absolute base objective. These are not
the same percentage.

Sources: [recording](../../src/optim_inject.jl#L919),
[saved fields](../../src/optim_inject.jl#L1019),
[penalty-share plot](../../src/optim_inject.jl#L1040).

## 11. Selecting an experimental setup

To disable a soft term, set lambda to zero while retaining `use_*`. To disable
a hard check, remove its presence-only `*_as_constraint` flag from the complete
argument list; do not append `false`. Keep monitoring step, case key, prior
mode, sample pairing, and case-level `inj_start` consistent with the experiment.
Run optimization through `sbatch` or `salloc`.

Example argument fragments:

```text
# PoF hard-only
--use_pof --eps_pof 0.01 --pof_as_constraint --lambda_pof 0
--tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime

# PoF soft-only: no --pof_as_constraint anywhere in the full arguments
--use_pof --eps_pof 0.01 --lambda_pof 8.5e8
--tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime

# PoF hard + soft
--use_pof --eps_pof 0.01 --pof_as_constraint --lambda_pof 8.5e8
--tau_pof 0.05 --kappa_pof 50 --risk_mode relative --weight_mode voltime

# CVaR hard-only
--use_cvar --alpha 0.01 --gamma_cvar 0.1 --cvar_as_constraint --lambda_cvar 0
--cvar_soft --kappa_cvar 50 --risk_mode relative --weight_mode voltime

# CVaR soft-only: no --cvar_as_constraint anywhere in the full arguments
--use_cvar --alpha 0.01 --gamma_cvar 0.1 --lambda_cvar 3.0e9
--cvar_soft --kappa_cvar 50 --risk_mode relative --weight_mode voltime

# CVaR hard + soft
--use_cvar --alpha 0.01 --gamma_cvar 0.1 --cvar_as_constraint --lambda_cvar 3.0e9
--cvar_soft --kappa_cvar 50 --risk_mode relative --weight_mode voltime
```

For a zero-exceedance discrete PoF criterion, use epsilon=0 with its matching
case and state history. The hard-only CVaR example retains `--cvar_soft` so only
the weight changes; a finite penalty multiplied by zero contributes nothing.
The values 8.5e8 and 3.0e9 are established weights, not automatic calibrations.

Output names do not encode lambda. Hard-only and hard-plus-soft runs with
otherwise identical settings share a case/sample path; different soft-only
weights also collide. Isolate outputs before comparisons. Changing shell
`CASE_TAG` alone does not change the Julia output path.
PoF and CVaR may use different modes, but enabling both hard checks requires
both to pass. For steps after the first, explicitly choose which `case_key`
provides the prior and case-level starting rate; do not mix histories silently.

## 12. Describing the mathematical problem in a paper

Let $M(q)$ be injected mass, $R(q)$ the unsmoothed risk metric,
$\widetilde R(q)$ its penalty metric, and $b$ the threshold. Define

$$
\Phi(q)=s_\kappa(\widetilde R(q)-b)-s_\kappa(0).
$$

| Mode | Mathematical problem | Interpretation |
|---|---|---|
| No risk handling | $\min_{q\geq0}-M(q)$ | Injection alone; without an upper bound, a finite optimum cannot be assumed |
| Soft-only | $\min_{q\geq0}[-M(q)+\lambda\Phi(q)]$, $\lambda>0$ | Risk-benefit tradeoff; the threshold need not be met |
| Hard-only | $\min_{q\geq0}-M(q)$ subject to $R(q)\leq b$ | Maximum injection under the risk bound |
| Hard + soft | $\min_{q\geq0}[-M(q)+\lambda\Phi(q)]$ subject to $R(q)\leq b$, $\lambda>0$ | Risk-penalized optimization with a hard limit |

The table omits the 1e-12 feasibility tolerance. With both risks disabled,
`case_key=auto` cannot infer the campaign case; this is not an established main
submission configuration. For PoF, use $R=P_{\mathrm{hard}}$,
$\widetilde R=P_{\mathrm{smooth}}$, $b=\varepsilon$; for CVaR, use
$R=C_{\mathrm{eval}}$, $\widetilde R=C_{\mathrm{smooth}}$, $b=\gamma$.
There are theoretically 4×4 role combinations, not 16 independently validated
campaign configurations or prior histories.

Hard-plus-soft and hard-only generally define different problems even with the
same feasible set. Smoothing a metric is separate from adding a soft risk term.
With fixed nonzero weights, the penalty participates in finite differences,
line-search comparisons, and the final objective; it is not merely a gradient
helper. The code does not gradually remove it and finish with a hard-only solve.

Describe the optimization problem separately from its numerical solution:
finite differences, nonnegative projection, backtracking, and `Inf` rejection
of infeasible candidates. For the established nonzero-lambda hard-constrained
experiments, a methods section stating only “maximize injection subject to a
PoF/CVaR threshold” would omit the risk term actually optimized.
