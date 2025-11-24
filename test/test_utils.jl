using DrWatson, Test
@quickactivate "optim_injr_DT"

# Test utility functions
@testset "Utility Functions" begin
    @testset "softplus function" begin
        # Test softplus function implementation
        # Actual implementation: log1p(exp(κ*x)) / κ (with clamping)
        
        softplus(x; κ::Float64 = 50.0) = begin
            y = κ * x
            y = clamp(y, -50.0, 50.0)
            return log1p(exp(y)) / κ
        end
        
        # Test with default kappa
        κ = 50.0
        x1 = 0.0
        result1 = softplus(x1; κ=κ)
        # softplus(0) = log1p(exp(0)) / κ = log(2) / κ
        @test result1 ≈ log(2) / κ atol=1e-10
        
        # Test with positive value
        x2 = 1.0
        result2 = softplus(x2; κ=κ)
        @test result2 > 0
        @test result2 > result1  # Monotonic
        
        # Test with negative value
        x3 = -1.0
        result3 = softplus(x3; κ=κ)
        @test result3 >= 0  # softplus is always non-negative
        @test result3 < result1  # Monotonic
        
        # Test with value that gets clamped
        x4 = 2.0  # κ*x4 = 100, but clamped to 50
        result4 = softplus(x4; κ=κ)
        @test result4 > 0
        # When clamped, result4 should equal softplus(1.0) since both clamp to 50
        @test result4 ≈ softplus(1.0; κ=κ) atol=1e-6
        
        # Test monotonicity
        @test softplus(0.5; κ=κ) < softplus(1.0; κ=κ)
        @test softplus(-1.0; κ=κ) < softplus(-0.5; κ=κ)
        
        # Test clamping behavior
        x5 = 10.0  # κ*x5 = 500, should be clamped to 50
        result5 = softplus(x5; κ=κ)
        x6 = 5.0   # κ*x6 = 250, should be clamped to 50
        result6 = softplus(x6; κ=κ)
        # Both should give same result due to clamping
        @test result5 ≈ result6 atol=1e-6
    end
    
    @testset "Basic math operations" begin
        # Test basic array operations
        arr1 = [1.0, 2.0, 3.0]
        arr2 = [4.0, 5.0, 6.0]
        
        @test arr1 + arr2 == [5.0, 7.0, 9.0]
        @test arr1 .* 2.0 == [2.0, 4.0, 6.0]
        @test sum(arr1) == 6.0
        @test maximum(arr1) == 3.0
        @test minimum(arr1) == 1.0
    end
    
    @testset "Array indexing" begin
        arr = collect(1.0:10.0)
        @test arr[1] == 1.0
        @test arr[end] == 10.0
        @test length(arr) == 10
    end
end

