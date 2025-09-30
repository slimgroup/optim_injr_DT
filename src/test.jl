using JLD2
# 文件路径
file = joinpath("data", "DT_control", "exp_name=step1",
    "CVaR__HARD__alpha=0.05__gamma=0.05__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
    "sample=1", "final.jld2")
# 加载数据
data = load(file)
# 提取 inj_rate_arr
inj_rate_arr = data["inj_rate_arr"]
# 找到最后一个非零元素
last_nonzero_idx = findlast(!iszero, inj_rate_arr)
last_nonzero_val = isnothing(last_nonzero_idx) ? nothing : inj_rate_arr[last_nonzero_idx]
println("File: ", file)
println("Last nonzero element index: ", last_nonzero_idx)
println("Last nonzero element value: ", last_nonzero_val)