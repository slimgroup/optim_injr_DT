using DrWatson, Test
using LinearAlgebra
@quickactivate "optim_injr_DT"

# Test optimization-related functions
@testset "Optimization Functions" begin
    @testset "Gradient computation basics" begin
        # Test basic gradient-like operations
        x = [1.0, 2.0, 3.0]
        f(x) = sum(x.^2)
        
        # Finite difference approximation
        eps = 1e-6
        grad_approx = zeros(length(x))
        for i in 1:length(x)
            x_plus = copy(x)
            x_plus[i] += eps
            grad_approx[i] = (f(x_plus) - f(x)) / eps
        end
        
        # Analytical gradient is 2*x
        grad_analytical = 2.0 .* x
        
        @test norm(grad_approx - grad_analytical) < 1e-4
    end
    
    @testset "Projection operations" begin
        # Test projection to bounds (common in optimization)
        x = [0.5, 1.5, -0.5, 2.5]
        lb = 0.0
        ub = 2.0
        
        x_proj = clamp.(x, lb, ub)
        @test all(x_proj .>= lb)
        @test all(x_proj .<= ub)
        @test x_proj == [0.5, 1.5, 0.0, 2.0]
    end
    
    @testset "Line search basics" begin
        # Test basic line search concepts
        x0 = [1.0, 1.0]
        p = [-1.0, -1.0]  # Search direction
        alpha = 0.5
        
        x_new = x0 + alpha * p
        @test x_new == [0.5, 0.5]
        
        # Test step size bounds
        alpha_min = 0.0
        alpha_max = 1.0
        @test alpha_min <= alpha <= alpha_max
    end
    
    @testset "Objective function properties" begin
        # Test that objective functions return scalars
        test_obj_values = [10.0, 20.0, 15.0]
        @test all(isfinite.(test_obj_values))
        @test all(test_obj_values .>= 0.0)  # Assuming non-negative objectives
        
        # Test objective improvement
        obj_old = 100.0
        obj_new = 80.0
        improvement = obj_old - obj_new
        @test improvement > 0.0
        @test improvement / obj_old ≈ 0.2
    end
    
    @testset "Convergence criteria" begin
        # Test relative improvement
        obj_prev = 100.0
        obj_curr = 99.0
        rel_improvement = abs(obj_prev - obj_curr) / max(1.0, abs(obj_curr))
        @test rel_improvement >= 0.0
        @test rel_improvement < 1.0
        
        # Test gradient norm
        grad = [0.01, 0.02, 0.03]
        grad_norm = norm(grad)
        @test grad_norm >= 0.0
        @test grad_norm < 1.0  # Small gradient suggests convergence
    end
end

