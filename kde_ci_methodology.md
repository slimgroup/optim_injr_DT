# KDE Curve and Confidence Interval Methodology

This document describes the detailed methodology for computing Kernel Density Estimation (KDE) curves and confidence intervals used in the injectivity distribution analysis.

## 1. KDE Curve

### Overview
The KDE curve provides a smooth, non-parametric estimate of the probability density function (PDF) from discrete sample data (128 injection rate values per case).

### Implementation Details

#### Kernel Type
- **Gaussian Kernel**: The implementation uses KernelDensity.jl's default Gaussian (normal) kernel
- The Gaussian kernel provides smooth density estimates and is mathematically well-behaved

#### Bandwidth Selection
- **Silverman's Rule**: When `kde_bandwidth = nothing`, the bandwidth is automatically selected using Silverman's rule of thumb
- Silverman's rule: `h = 0.9 * min(σ, IQR/1.34) * n^(-1/5)`
  - `σ`: standard deviation of the data
  - `IQR`: interquartile range
  - `n`: number of samples (typically 128)
- This rule provides a good balance between smoothness and detail preservation

#### Computation Steps

1. **Compute KDE**:
   ```julia
   kde_result = kde(data)  # Uses Gaussian kernel + Silverman's rule for bandwidth
   ```

2. **Scale KDE to Match Histogram Frequency**:
   ```julia
   kde_scaled = kde_result.density .* length(data) .* bin_width
   ```
   - `kde_result.density`: probability density values
   - `length(data)`: number of samples (e.g., 128)
   - `bin_width`: histogram bin width
   - Result: KDE curve height matches histogram frequency scale

3. **Plot**:
   - X-axis: `kde_result.x` (evaluation points from KDE)
   - Y-axis: `kde_scaled` (frequency-scaled density values)

### Purpose
The KDE curve provides a smooth visualization of the injection rate distribution, complementing the discrete histogram representation.

---

## 2. Confidence Interval

### Overview
Confidence intervals are computed for the Cumulative Distribution Function (CDF) to quantify uncertainty in the fracture probability estimates at each injection rate value.

### Implementation Details

#### CDF Computation from KDE

1. **Create Evaluation Grid**:
   ```julia
   x_grid = collect(range(x_min, stop=x_max, length=num_grid))  # Default: 16,000 points
   dx = x_grid[2] - x_grid[1]  # Grid spacing
   ```

2. **Compute PDF Values**:
   ```julia
   pdf_vals = pdf(kde_result, x_grid)
   ```
   - Evaluates the KDE PDF at each grid point

3. **Compute CDF by Cumulative Sum**:
   ```julia
   cdf_vals = cumsum(pdf_vals) .* dx
   cdf_vals = cdf_vals ./ cdf_vals[end]  # Normalize to ensure CDF ends at 1.0
   ```
   - Integrates the PDF to obtain the CDF
   - Normalization ensures the CDF reaches exactly 1.0 at the maximum value

#### Confidence Interval Calculation

**Assumption**: At each injection rate value (x), the fracture probability follows a **Bernoulli distribution**.

**Method**: **Wald method** for proportion confidence intervals

**Formula**:
```julia
n = length(data)  # Sample size (typically 128)
z = quantile(Normal(), 1 - (1 - conf_level) / 2)  # z-score for 95% CI: z ≈ 1.96

for each grid point i:
    p_hat = cdf_vals[i]  # Estimated fracture probability at x_grid[i]
    se = sqrt(p_hat * (1 - p_hat) / n)  # Standard error (Bernoulli distribution)
    ci_lower[i] = max(0.0, p_hat - z * se)  # Lower confidence bound
    ci_upper[i] = min(1.0, p_hat + z * se)  # Upper confidence bound
```

**Key Points**:
- **Standard Error**: `se = sqrt(p̂(1-p̂)/n)` is the standard error for a proportion under the Bernoulli assumption
- **Confidence Level**: Default is 95% (`conf_level = 0.95`)
- **Bounds**: `ci_lower` and `ci_upper` are clipped to [0, 1] to ensure valid probability values

### Interpretation
- **ci_upper**: Upper confidence bound (higher probability) - reaches threshold at **smaller** injection rate = **Left CI** (conservative estimate)
- **ci_lower**: Lower confidence bound (lower probability) - reaches threshold at **larger** injection rate = **Right CI** (less conservative estimate)
- The confidence interval quantifies uncertainty in the CDF estimate due to finite sample size

---

## 3. Threshold Crossing

### Overview
Threshold crossing identifies the injection rate values at which the CDF and confidence intervals reach a specific fracture probability threshold (default: 1%).

### Implementation Details

#### Finding Crossing Points

For a given threshold (e.g., 1% fracture probability):

1. **CDF Crossing**:
   ```julia
   idx_cdf = findfirst(x -> x >= threshold, cdf)
   x_cdf = x_grid[idx_cdf]  # Injection rate where CDF reaches threshold
   ```
   - Finds the first grid point where CDF ≥ threshold
   - `x_cdf`: Point estimate of injection rate at threshold

2. **Left CI Crossing** (Conservative Estimate):
   ```julia
   idx_upper = findfirst(x -> x >= threshold, ci_upper)
   x_left_ci = x_grid[idx_upper]
   ```
   - `ci_upper` reaches threshold **earlier** (at smaller x) because it's the upper bound
   - `x_left_ci`: Conservative injection rate estimate (lower value)

3. **Right CI Crossing** (Less Conservative Estimate):
   ```julia
   idx_lower = findfirst(x -> x >= threshold, ci_lower)
   x_right_ci = x_grid[idx_lower]
   ```
   - `ci_lower` reaches threshold **later** (at larger x) because it's the lower bound
   - `x_right_ci`: Less conservative injection rate estimate (higher value)

### Interpretation

- **x_left_ci < x_cdf < x_right_ci**: The confidence interval provides a range of plausible injection rates
- **x_left_ci**: Most conservative choice (safest, lowest injection rate)
- **x_cdf**: Point estimate (median expectation)
- **x_right_ci**: Less conservative choice (higher injection rate, but with lower confidence)

### Visualization
These crossing points are annotated on the CDF plots with:
- **Left CI**: Annotation at `(x_left_ci, 0.01)` with label "Left CI"
- **CDF**: Annotation at `(x_cdf, 0.01)` with label "CDF"
- **Right CI**: Not annotated (to reduce clutter, but can be added if needed)

---

## Summary

1. **KDE Curve**: Uses Gaussian kernel with Silverman's rule for bandwidth selection, scaled to match histogram frequency
2. **Confidence Interval**: Computed from KDE-derived CDF using Wald method with Bernoulli distribution assumption
3. **Threshold Crossing**: Identifies injection rates where CDF and CI bounds reach target fracture probability (1%)

This methodology provides a robust, statistically sound approach to estimating injection rate distributions and their associated uncertainties for fracture probability assessment.

