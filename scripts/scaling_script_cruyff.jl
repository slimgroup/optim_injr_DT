# Run Jutul simulation and do the scaling analysis.

using Dates

timings = Dict{Int, Float64}()

function benchmark_run(nthreads::Int)
    println("Running with $nthreads threads...")
    t0 = time()  # More precise than `now()`
    run(`julia --threads=$nthreads scripts/scaling_jutul.jl`)
    duration = time() - t0
    println("Completed in ", duration, " seconds.")
    timings[nthreads] = duration
end

# for t in [1, 2, 4, 8, 16, 32]
#     benchmark_run(t)
# end

for t in [8, 16, 32]
    benchmark_run(t)
end

using Plots
using DrWatson

threads = sort(collect(keys(timings)))
runtimes = [timings[t] for t in threads]

plt = plot(
    threads, runtimes;
    lw=3,
    marker=:o,
    xlabel="Number of Threads",
    ylabel="Runtime (s)",
    title="Strong Scaling of Jutul Simulation",
    legend=false
)

# Define where to save
cruyff_plot_path_prefix = "/slimdata/jason/optim_injr_DT/plots"
plot_path = joinpath(
    cruyff_plot_path_prefix,
    sim_name,
    savename(@strdict(exp_name); digits=6),
    "states"
)

# # Ensure directory exists
# mkpath(plot_path)

# Use safesave with Plots backend: save as PNG or PDF
safesave(joinpath(plot_path, "scaling_plot.png"), plt)


baseline = runtimes[1]
speedup = baseline ./ runtimes
efficiency = speedup ./ threads

println("Threads\tRuntime(s)\tSpeedup\tEfficiency")
for i in eachindex(threads)
    println("$(threads[i])\t$(round(runtimes[i], digits=2))\t\t$(round(speedup[i], digits=2))\t$(round(efficiency[i]*100, digits=1))%")
end


