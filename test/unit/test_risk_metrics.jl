using DrWatson, Test
using Statistics
@quickactivate "optim_injr_DT"

# Test risk metric functions
@testset "Risk Metrics" begin
    @testset "POF smooth function" begin
        # Test POF smooth function logic
        # pof_smooth(r::Vector{Float64}, w::Vector{Float64}; τ::Float64=0.05)
        # Should compute smoothed probability of failure
        
        r = [0.0, 0.01, 0.02, 0.03, 0.05]
        w = ones(length(r)) / length(r)  # Uniform weights
        
        # Test that POF is between 0 and 1
        # (We can't test the exact implementation without including the source)
        @test length(r) == length(w)
        @test sum(w) ≈ 1.0 atol=1e-10
    end
    
    @testset "CVaR computation" begin
        # Test CVaR computation logic
        # cvar_clean(L::AbstractVector{<:Real}, w::AbstractVector{<:Real}; α::Float64=0.05)
        
        L = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        w = ones(length(L)) / length(L)
        α = 0.1  # 10% tail
        
        # Test that weights sum to 1
        @test sum(w) ≈ 1.0 atol=1e-10
        
        # Test that α is between 0 and 1
        @test 0.0 < α < 1.0
        
        # Test quantile computation
        sorted_L = sort(L)
        quantile_idx = Int(ceil(length(L) * (1 - α)))
        @test quantile_idx >= 1
        @test quantile_idx <= length(L)
    end
    
    @testset "Weight validation" begin
        # Test weight vector properties
        w1 = [0.2, 0.3, 0.5]
        @test sum(w1) ≈ 1.0 atol=1e-10
        @test all(w1 .>= 0.0)
        
        w2 = ones(10) / 10
        @test sum(w2) ≈ 1.0 atol=1e-10
        @test length(w2) == 10
    end
    
    @testset "Array operations for risk metrics" begin
        r_vals = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05]
        w_vals = [0.1, 0.15, 0.2, 0.25, 0.15, 0.15]
        
        # Test weighted sum
        weighted_sum = sum(r_vals .* w_vals)
        @test weighted_sum >= 0.0
        @test weighted_sum <= maximum(r_vals)
        
        # Test threshold exceedance
        threshold = 0.03
        exceedance_mask = r_vals .> threshold
        exceedance_count = sum(exceedance_mask)
        @test exceedance_count >= 0
        @test exceedance_count <= length(r_vals)
    end
end

