using JLD2
# File path
file = joinpath("data", "DT_control", "exp_name=step1",
    "CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "sample=1", "final.jld2")
# Load data
data = load(file)
# Extract inj_rate_arr
inj_rate_arr = data["inj_rate_arr"]
# Find the last nonzero element
last_nonzero_idx = findlast(!iszero, inj_rate_arr)
last_nonzero_val = isnothing(last_nonzero_idx) ? nothing : inj_rate_arr[last_nonzero_idx]
println("File: ", file)
println("Last nonzero element index: ", last_nonzero_idx)
println("Last nonzero element value: ", last_nonzero_val)