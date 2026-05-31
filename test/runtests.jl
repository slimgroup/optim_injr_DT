using DrWatson, Test
@quickactivate "optim_injr_DT"

# Run test suite
println("Starting tests for optim_injr_DT")
ti = time()

# Include test files (unit tests first, then integration)
include("unit/test_utils.jl")
include("unit/test_risk_metrics.jl")
include("unit/test_data_io.jl")
include("unit/test_optimization.jl")
include("integration/test_ds_minimal.jl")

ti = time() - ti
println("\nAll tests completed!")
println("Test took total time of:")
println(round(ti, digits = 3), " seconds")
