using KernelDensity, Optim, Statistics

# Leave-one-out KDE log-likelihood loss
function loo_cv_loglik(h, data)
    n = length(data)
    if h <= 0
        return Inf
    end

    total_loglik = 0.0

    for i in 1:n
        # Exclude i-th sample
        data_loo = vcat(data[1:i-1], data[i+1:end])

        # Compute KDE using bandwidth h
        kde_loo = kde(data_loo; bandwidth=h)

        # Interpolate the KDE for data[i]
        f̂ = LinearInterpolation(kde_loo.x, kde_loo.density, extrapolation_bc=Line())
        density_at_xi = f̂(data[i])

        # Accumulate log-likelihood (small value to avoid log(0))
        total_loglik += log(density_at_xi + 1e-12)
    end

    return -total_loglik  # Minimize negative log-likelihood
end

# Run optimization (you can adjust bounds)
optimal_result = optimize(h -> loo_cv_loglik(h, injr_dist), 0.0001, 0.01)
optimal_bandwidth = Optim.minimizer(optimal_result)
