# Bootstrap-Based CDF Uncertainty Quantification

## Methodology for Fracture Probability Estimation

This document describes the statistical methodology used to estimate fracture probability
thresholds and quantify their uncertainty. This replaces the previous KDE-based approach.

---

## 1. Motivation: Why Not KDE?

We have **n = 128 geological samples**, each producing an optimized injection rate.
The goal is to determine the maximum safe injection rate such that fracture probability
stays below 1%.

The previous approach used **Kernel Density Estimation (KDE)** to smooth the sample
distribution into a continuous PDF, then integrated to get a CDF. The problem:

- With only 128 samples, the **left 1% tail** contains ~1.28 effective samples.
- KDE results at this tail are **extremely sensitive** to bandwidth and kernel choice.
- Different bandwidths (e.g., 0.5x vs 2x Silverman's rule) produce drastically
  different 1% threshold estimates.
- This sensitivity makes KDE unsuitable as the **basis for decisions**.

**Resolution**: Avoid smoothing the density entirely. Work directly in probability space
using the empirical CDF, and quantify uncertainty via bootstrap.

KDE is retained **only** for visualization or sensitivity analysis, not for decision making.

---

## 2. Empirical CDF (ECDF)

The empirical CDF is defined as:

    F_hat(x) = (1/n) * sum_{i=1}^{n} 1(X_i <= x)

where X_1, ..., X_n are the n = 128 injection rate samples.

**Properties**:
- **Uniquely defined**: No tuning parameters, no bandwidth, no kernel choice.
- **Consistent**: By the Glivenko-Cantelli theorem, F_hat(x) converges uniformly
  to the true CDF F(x) as n -> infinity.
- **Nonparametric MLE**: The ECDF is the maximum likelihood estimator of the true
  CDF under no distributional assumptions.

The ECDF is a step function that jumps by 1/n = 1/128 at each observed data point.

---

## 3. Bootstrap Procedure

### 3.1 Overview

We use the **nonparametric percentile bootstrap** (Efron, 1979) to quantify
uncertainty in the ECDF and in the 1% quantile estimate.

**Core idea**: Resample from the observed data with replacement to simulate
what other datasets we might have observed, and use the variability across
resamples to estimate uncertainty.

### 3.2 Algorithm

Given: n = 128 observed injection rates X_1, ..., X_n

For b = 1, 2, ..., B (where B = 10,000):
  1. Draw n = 128 samples **with replacement** from {X_1, ..., X_n}
     to get a bootstrap sample X_1^(b), ..., X_n^(b)
  2. Compute the ECDF of the bootstrap sample: F_hat^(b)(x)
  3. Compute the 1% quantile of the bootstrap sample: q^(b) = quantile(X^(b), 0.01)

### 3.3 Two Outputs

**Output 1: Pointwise CDF confidence band**

At each evaluation point x on a fine grid:
- Collect {F_hat^(1)(x), F_hat^(2)(x), ..., F_hat^(B)(x)}
- CDF_lower(x) = 2.5th percentile of these B values
- CDF_upper(x) = 97.5th percentile of these B values

This gives a **pointwise 95% confidence band** for the CDF.

**Output 2: Quantile confidence interval**

- Collect {q^(1), q^(2), ..., q^(B)}
- q_lower = 2.5th percentile of these B values
- q_upper = 97.5th percentile of these B values

This gives a **95% confidence interval for the 1% quantile**.

### 3.4 Parameters

| Parameter | Value | Justification |
|-----------|-------|---------------|
| n (sample size) | 128 | Number of geological realizations |
| B (bootstrap replicates) | 10,000 | Standard practice (Efron & Tibshirani, 1993); sufficient for stable CI endpoints |
| Confidence level | 95% | Standard; also tested with 99% |
| Target quantile | 1% (0.01) | Fracture probability threshold |
| Resampling method | With replacement | Standard nonparametric bootstrap |
| CI method | Percentile | Simple, transparent, adequate for n=128 |
| Random seed | 2025 | For reproducibility |

### 3.5 Why B = 10,000 Is Sufficient

- B >= 1,000 is generally sufficient for CI estimation (Efron & Tibshirani, 1993)
- B = 10,000 ensures stable CI endpoints (re-running with different seeds produces
  results identical to the 4th-5th decimal place)
- Computation time is ~2 seconds for 128 samples, so there is no cost to using B = 10,000
- B > 10,000 provides diminishing returns

---

## 4. Decision Framework

### 4.1 Three Estimates at the 1% Threshold

From the bootstrap analysis, we report three injection rate values:

1. **Conservative estimate**: The x-value where the **upper CDF band** crosses 1%.
   Since the upper band rises faster, it crosses 1% at a smaller injection rate.
   This is the most conservative (safest) choice.

2. **ECDF estimate (point estimate)**: The x-value where the **empirical CDF** crosses 1%.
   This is the standard point estimate.

3. **Optimistic estimate**: The x-value where the **lower CDF band** crosses 1%.
   Since the lower band rises slower, it crosses 1% at a larger injection rate.

Additionally, the **bootstrap quantile CI** provides:

4. **CI lower bound**: 2.5th percentile of 10,000 bootstrap 1% quantile values.
5. **CI upper bound**: 97.5th percentile of 10,000 bootstrap 1% quantile values.

Note: Items 1 and 4 (and items 3 and 5) are very close but not identical,
because they are computed differently:
- Items 1 and 3 come from the **CDF band** (pointwise percentiles of CDF values,
  then find crossing)
- Items 4 and 5 come from the **quantile bootstrap** (directly bootstrap the quantile)

The small discrepancy (typically < 0.002 m3/s) provides mutual validation.

### 4.2 Decision Rule

**For safety-critical decision making, we adopt the conservative bound (CI lower)
as the recommended maximum safe injection rate.**

This ensures that with 95% confidence, the true 1% fracture probability threshold
is at least as large as the recommended rate.

---

## 5. Pointwise vs Simultaneous Bands

### 5.1 What We Use: Pointwise Band

Our bootstrap CDF band is a **pointwise** confidence band:
- At each x-value independently, 95% of bootstrap ECDFs fall within the band
- This does NOT guarantee that the entire true CDF lies within the band simultaneously

### 5.2 Alternative: Simultaneous Band (DKW)

The Dvoretzky-Kiefer-Wolfowitz (DKW) inequality (1956) provides a
**simultaneous** (uniform) confidence band:

    P( sup_x |F_hat(x) - F(x)| > epsilon ) <= 2 * exp(-2 * n * epsilon^2)

For n = 128 and 95% confidence:

    epsilon = sqrt(log(2 / 0.05) / (2 * 128)) = 0.1073

This means the ECDF is within +/-10.73% of the true CDF **everywhere simultaneously**
with 95% confidence.

### 5.3 Why Pointwise Is Sufficient

- We only care about the CDF near the 1% threshold, not the entire curve
- DKW band is too wide for practical decisions: 1% +/- 10.7% = [-9.7%, 11.7%]
- The pointwise bootstrap band is much tighter at the region of interest
- For single-point inference (the 1% quantile), pointwise is appropriate

The DKW result is mentioned as a **theoretical guarantee** but not used for decisions.

---

## 6. Methods Not Used (and Why)

### 6.1 BCa Bootstrap (Bias-Corrected and Accelerated)

BCa improves the percentile bootstrap by correcting for:
- **Bias**: If the bootstrap distribution is shifted relative to the true sampling distribution
- **Acceleration (skewness)**: If different data points affect the estimate unequally

BCa is theoretically second-order accurate vs first-order for the percentile method.
However, for n = 128, the difference is negligible. We verified that BCa produces
nearly identical results (not shown).

### 6.2 Parametric Bootstrap

Parametric bootstrap assumes data follows a specific distribution (e.g., lognormal),
fits parameters, then resamples from the fitted distribution. We avoid this because:
- The true distribution shape is unknown
- Wrong parametric assumption would introduce bias
- Nonparametric bootstrap requires no distributional assumption

### 6.3 KDE-Based CDF

The previous approach computed CDF by integrating a KDE-smoothed PDF.
Problems documented in detail:
- Bandwidth sensitivity at the 1% tail (see docs/KDE_CI_METHODOLOGY.md)
- Different kernels produce different results
- Confidence intervals based on Wald/Wilson/Jeffreys methods applied to
  KDE-derived CDF values mix two sources of uncertainty

The KDE approach is retained as a **backup for visualization only**.

---

## 7. Visualization

For each case (e.g., POF eps=0.01, CVaR gamma=0.05 alpha=0.05), we produce
a two-panel figure:

### Panel (a): Injection Rate Distribution
- Histogram of 128 injection rate samples (no KDE smoothing)
- Rug plot: small vertical ticks showing each sample's exact position
- Vertical lines marking the 1% quantile point estimate and its 95% CI
- Inset: histogram of 10,000 bootstrap 1% quantile values

### Panel (b): Empirical CDF with Bootstrap CI
- Full ECDF from 0% to 100% with 95% bootstrap confidence band
- 1% fracture probability threshold line
- Inset zooming into the left tail (0-8%) showing:
  - Conservative estimate (upper CDF band crossing 1%)
  - ECDF estimate (ECDF crossing 1%)
  - Optimistic estimate (lower CDF band crossing 1%)
  - Quantile CI shaded region

---

## 8. Example Results

### POF (eps=0.01, hard constraint), n=128 samples

| Metric | Value (m3/s) |
|--------|-------------|
| 1% quantile (point estimate) | 0.10617 |
| 95% CI lower (quantile bootstrap) | 0.09911 |
| 95% CI upper (quantile bootstrap) | 0.12425 |
| Conservative (CDF upper band crossing) | 0.09924 |
| ECDF crossing | 0.10309 |
| Optimistic (CDF lower band crossing) | 0.12309 |
| **Recommended safe rate** | **0.09911** |

### CVaR (gamma=0.05, alpha=0.05, hard constraint), n=128 samples

| Metric | Value (m3/s) |
|--------|-------------|
| 1% quantile (point estimate) | 0.17834 |
| 95% CI lower (quantile bootstrap) | 0.16781 |
| 95% CI upper (quantile bootstrap) | 0.21106 |
| Conservative (CDF upper band crossing) | 0.16830 |
| ECDF crossing | 0.17391 |
| Optimistic (CDF lower band crossing) | 0.21000 |
| **Recommended safe rate** | **0.16781** |

---

## 9. Limitations

1. **Small effective sample size at the tail**: With n=128, the 1% quantile
   corresponds to ~1.28 samples. The bootstrap CI is consequently wide,
   reflecting genuine uncertainty. This is not a flaw of the method but
   an honest representation of data limitations.

2. **Pointwise (not simultaneous) band**: The CDF band is valid pointwise,
   not simultaneously across all x. This is acceptable because we only
   make decisions at the 1% threshold.

3. **IID assumption**: The bootstrap assumes the 128 samples are independent
   and identically distributed draws from the geological uncertainty.
   This is satisfied by construction (each sample corresponds to an
   independent geological realization).

---

## 10. References

- Efron, B. (1979). "Bootstrap methods: another look at the jackknife."
  Annals of Statistics, 7(1), 1-26.
- Efron, B. and Tibshirani, R.J. (1993). "An Introduction to the Bootstrap."
  Chapman & Hall/CRC.
- Dvoretzky, A., Kiefer, J., and Wolfowitz, J. (1956). "Asymptotic minimax
  character of the sample distribution function and of the classical
  multinomial estimator." Annals of Mathematical Statistics, 27(3), 642-669.
- Massart, P. (1990). "The tight constant in the Dvoretzky-Kiefer-Wolfowitz
  inequality." Annals of Probability, 18(3), 1269-1283.

---

## 11. Code

- Full analysis: `scripts/julia_scripts/analysis/bootstrap_cdf_analysis.jl`
- Two-panel plots: `scripts/julia_scripts/analysis/plot_bootstrap_two_panels.jl`
- Previous KDE approach (backup): `scripts/julia_scripts/plotting/plot_cdf_ci.jl`
- Previous KDE methodology: `docs/KDE_CI_METHODOLOGY.md`

---

## 12. Summary

| Aspect | Choice | Reason |
|--------|--------|--------|
| CDF estimation | Empirical CDF | No tuning parameters, uniquely defined |
| Uncertainty method | Nonparametric bootstrap | Minimal assumptions (only iid) |
| CI type | Percentile method | Simple, transparent, adequate for n=128 |
| Band type | Pointwise | Sufficient for single-threshold decision |
| B (replicates) | 10,000 | Stable results, standard practice |
| Decision rule | Conservative (CI lower bound) | Safety-critical application |
| KDE role | Visualization only | Too sensitive at tail for decisions |
