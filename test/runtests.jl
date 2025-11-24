using DrWatson, Test
@quickactivate "optim_injr_DT"

# Run test suite
println("Starting tests for optim_injr_DT")
ti = time()

# Include test files
include("test_utils.jl")
include("test_risk_metrics.jl")
include("test_data_io.jl")
include("test_optimization.jl")

ti = time() - ti
println("\nAll tests completed!")
println("Test took total time of:")
println(round(ti, digits = 3), " seconds")
