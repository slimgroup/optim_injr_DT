#!/usr/bin/env julia
# Verify the calculation logic matches user's requirements

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2

const ROOT = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const FORWARD_STEP = 2
const INJ_START = 0.0001

function verify_calculation(final_path::String)
    println("\n" * "=" ^ 80)
    println("Verifying: $final_path")
    println("=" ^ 80)
    
    data = load(final_path)
    inj_arr = data["inj_rate_arr"]
    
    # Step 1: Load inj_rate_arr
    col1 = ndims(inj_arr) == 1 ? collect(inj_arr) : vec(view(inj_arr, :, 1))
    println("Step 1: Loaded inj_rate_arr, length: $(length(col1))")
    println("  First 5 elements: $(col1[1:min(5, length(col1))])")
    
    # Step 2: Find last nonzero element
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    if idx === nothing
        println("  ERROR: No nonzero element found!")
        return
    end
    
    last_nonzero = clean[idx]
    println("Step 2: Found last nonzero element")
    println("  Index: $idx")
    println("  Value: $last_nonzero")
    
    # Step 3: Construct array using last_nonzero
    inj_rate_full = collect(range(INJ_START, last_nonzero, FORWARD_STEP * 6))
    println("Step 3: Constructed array using last_nonzero")
    println("  Array length: $(length(inj_rate_full))")
    println("  Array: $inj_rate_full")
    
    # Step 4: Select index 6 (the 7th element in 1-based indexing)
    if length(inj_rate_full) >= 7
        inj_rate_at_index6 = inj_rate_full[7]
        println("Step 4: Selected index 6 (inj_rate[7])")
        println("  Value: $inj_rate_at_index6")
        
        # Step 5: Take average with inj_start
        result = (inj_rate_at_index6 + INJ_START) / 2.0
        println("Step 5: Take average with inj_start")
        println("  Result: $result = ($inj_rate_at_index6 + $INJ_START) / 2.0")
        return result
    else
        println("  ERROR: Array too short!")
        return nothing
    end
end

# Test a few samples
test_files = [
    "POF__HARD__eps=0.0__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0/sample=1/final.jld2",
    "POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0/sample=1/final.jld2",
    "CVaR__HARD__alpha=0.001__gamma=0.0__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=1/final.jld2",
    "CVaR__HARD__alpha=0.01__gamma=0.0__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0/sample=1/final.jld2",
]

println("=" ^ 80)
println("Verification of Calculation Logic")
println("=" ^ 80)
println("\nRequirements:")
println("1. Load inj_rate_arr from final.jld2")
println("2. Find last nonzero element")
println("3. Construct: collect(range(inj_start, last_nonzero, forward_step * 6))")
println("4. Select index 6 (inj_rate[7])")
println("5. Take average: (inj_rate[7] + inj_start) / 2.0")
println("=" ^ 80)

for test_file in test_files
    final_path = joinpath(ROOT, test_file)
    if isfile(final_path)
        verify_calculation(final_path)
    else
        println("\nFile not found: $final_path")
    end
end

println("\n" * "=" ^ 80)
println("Verification complete!")
println("=" ^ 80)

