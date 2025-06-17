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

for t in [2, 4, 8, 16, 32]
    benchmark_run(t)
end

using Plots

threads = sort(collect(keys(timings)))
runtimes = [timings[t] for t in threads]

plot(threads, runtimes;
    lw=3,
    marker=:o,
    xlabel="Number of Threads",
    ylabel="Runtime (s)",
    title="Strong Scaling of Jutul Simulation",
    legend=false
)
savefig("scaling_plot.png")

baseline = runtimes[1]
speedup = baseline ./ runtimes
efficiency = speedup ./ threads

println("Threads\tRuntime(s)\tSpeedup\tEfficiency")
for i in eachindex(threads)
    println("$(threads[i])\t$(round(runtimes[i], digits=2))\t\t$(round(speedup[i], digits=2))\t$(round(efficiency[i]*100, digits=1))%")
end


