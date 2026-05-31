# Activate the project environment
using Pkg
Pkg.activate(".")
Pkg.instantiate()

using DrWatson
@quickactivate "optim_injr_DT"

using Dates
using PyPlot

timings = Dict{Int, Float64}()

function benchmark_run(nthreads::Int)
    println("Running with $nthreads threads...")
    t0 = time()
    run(`julia --threads=$nthreads scripts/julia_scripts/utilities/scaling_jutul_cruyff.jl`)
    duration = time() - t0
    println("Completed in ", duration, " seconds.")
    timings[nthreads] = duration
end

println("Running with default threads...")
t0 = time()
run(`julia scripts/julia_scripts/utilities/scaling_jutul_cruyff.jl`)
duration = time() - t0
println("Completed in ", duration, " seconds.")

for t in [1, 2, 4, 8, 16, 32]
    benchmark_run(t)
end

# for t in [8, 16, 32]
#     benchmark_run(t)
# end

# Prepare data
threads = sort(collect(keys(timings)))
runtimes = [timings[t] for t in threads]

# Plot using PyPlot
fig, ax = subplots(figsize=(8, 5))
ax.plot(threads, runtimes, "o-", linewidth=2)

ax.set_xlabel("Number of Threads", fontsize=14)
ax.set_ylabel("Runtime (s)", fontsize=14)
ax.set_title("Strong Scaling of Jutul Simulation", fontsize=16)
ax.grid(true)

# Define save path
cruyff_plot_path_prefix = "/slimdata/jason/optim_injr_DT/plots"
sim_name = "DT_control"
exp_name = "scaling"
plot_path = joinpath(
    cruyff_plot_path_prefix,
    sim_name,
    savename(@strdict(exp_name); digits=6),
    "states"
)

mkpath(plot_path)

# Save figure using DrWatson's safesave (PyPlot-compatible)
safesave(joinpath(plot_path, "scaling_plot.png"), fig)

# Optional: also save timings
safesave(joinpath(plot_path, "scaling_timings.jld2"), Dict("timings" => timings))

# Compute speedup and efficiency
baseline = runtimes[1]
speedup = baseline ./ runtimes
efficiency = speedup ./ threads

println("Threads\tRuntime(s)\tSpeedup\tEfficiency")
for i in eachindex(threads)
    println("$(threads[i])\t$(round(runtimes[i], digits=2))\t\t$(round(speedup[i], digits=2))\t$(round(efficiency[i]*100, digits=1))%")
end
