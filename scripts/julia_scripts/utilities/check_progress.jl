# Quick script to check progress of threshold sensitivity analysis
# Usage: 
#   julia scripts/julia_scripts/utilities/check_progress.jl 128
#   julia scripts/julia_scripts/utilities/check_progress.jl        (defaults to 128)

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using Dates

function main()
    # Parse command line argument
    idx_num = 128  # default
    if length(ARGS) > 0
        try
            idx_num = parse(Int, ARGS[1])
        catch
            println("Usage: julia scripts/check_progress.jl [idx_num]")
            println("  idx_num: sample index (default: 128)")
            return
        end
    end
    
    checkpoint_path = datadir("DT_control", "exp_name=step1", "threshold_sensitivity",
                              "progress_checkpoint__sample=$(idx_num).jld2")
    
    if !isfile(checkpoint_path)
        println("=" ^ 80)
        println("PROGRESS CHECK - Sample $(idx_num)")
        println("=" ^ 80)
        println()
        println("❌ No checkpoint file found at:")
        println("   ", checkpoint_path)
        println()
        println("This means either:")
        println("   1. The analysis hasn't started yet")
        println("   2. The analysis completed and checkpoint was removed")
        println("   3. The analysis is running but hasn't completed any threshold yet")
        println()
        println("💡 Checking for running processes...")
        try
            # Use shell command directly with run
            proc_output = ""
            try
                # Run: sh -c "ps aux | grep threshold_sensitivity"
                proc_output = read(Cmd(`sh`, [`-c`, "ps aux | grep threshold_sensitivity"]), String)
            catch e
                # If grep fails (no matches), it's okay
                proc_output = ""
            end
            lines = split(proc_output, '\n')
            julia_procs = filter(l -> occursin("julia", l) && occursin("threshold_sensitivity", l) && !occursin("grep", l), lines)
            if !isempty(julia_procs)
                println("   ✓ Found running process!")
                for proc in julia_procs
                    # Extract PID and command
                    parts = split(proc)
                    if length(parts) >= 2
                        pid = parts[2]
                        cmd_start = findfirst(x -> occursin("julia", x), parts)
                        if cmd_start !== nothing
                            cmd = join(parts[cmd_start:end], " ")
                            println("   PID: $pid")
                            println("   Command: $(cmd[1:min(100, length(cmd))])...")
                        end
                    end
                end
                println("   The analysis is likely running but hasn't saved checkpoint yet.")
                println("   (Checkpoint is saved when each threshold starts)")
            else
                println("   ✗ No running process found")
            end
        catch e
            println("   (Could not check processes: ", e, ")")
        end
        println()
        println("💡 Alternative: Check for output files:")
        output_dir = datadir("DT_control", "exp_name=step1", "threshold_sensitivity")
        if isdir(output_dir)
            println("   Output directory exists: ", output_dir)
            try
                files = readdir(output_dir)
                if !isempty(files)
                    println("   Found $(length(files)) files/directories")
                    println("   Recent files (sorted by modification time):")
                    # Sort by modification time
                    file_info = []
                    for f in files
                        filepath = joinpath(output_dir, f)
                        if isfile(filepath) || isdir(filepath)
                            push!(file_info, (f, mtime(filepath)))
                        end
                    end
                    sort!(file_info, by=x->x[2], rev=true)
                    for (f, mtime_val) in file_info[1:min(5, length(file_info))]
                        mtime_str = Dates.format(Dates.unix2datetime(mtime_val), "yyyy-mm-dd HH:MM:SS")
                        file_type = isdir(joinpath(output_dir, f)) ? "[DIR]" : "[FILE]"
                        println("     $file_type $f (modified: $mtime_str)")
                    end
                else
                    println("   Directory is empty")
                end
            catch e
                println("   (Error reading directory: ", e, ")")
            end
        else
            println("   Output directory does not exist yet")
        end
        println("=" ^ 80)
        return
    end
    
    data = load(checkpoint_path)
    
    println("=" ^ 80)
    println("PROGRESS CHECK - Sample $(idx_num)")
    println("=" ^ 80)
    println()
    
    completed = get(data, "completed_thresholds", Float64[])
    current = get(data, "current_threshold", nothing)
    current_idx = get(data, "current_index", 0)
    total = get(data, "total_thresholds", 0)
    elapsed = get(data, "overall_elapsed", 0.0)
    timestamp = get(data, "timestamp", nothing)
    
    println("Status:")
    println("  Completed thresholds: $(length(completed))/$(total)")
    if !isempty(completed)
        println("  Completed: ", completed)
    end
    if current !== nothing
        println("  Currently running: $(current) MPa (threshold $(current_idx)/$(total))")
    end
    println()
    
    if elapsed > 0
        println("Time:")
        println("  Total elapsed: $(round(elapsed/60, digits=1)) minutes ($(round(elapsed/3600, digits=2)) hours)")
        if length(completed) > 0
            avg_per_thresh = elapsed / length(completed)
            remaining = total - length(completed)
            if current !== nothing
                remaining -= 1  # Don't count current one
            end
            if remaining > 0
                est_remaining = avg_per_thresh * remaining
                println("  Average per threshold: $(round(avg_per_thresh/60, digits=1)) minutes")
                println("  Estimated remaining: $(round(est_remaining/60, digits=1)) minutes ($(round(est_remaining/3600, digits=2)) hours)")
            end
        end
        println()
    end
    
    if timestamp !== nothing
        println("Last update: ", timestamp)
        age = now() - timestamp
        println("  Age: $(round(age.value/1000/60, digits=1)) minutes ago")
        if age.value > 30*60*1000  # 30 minutes
            println("  ⚠️  WARNING: No update for >30 minutes. Program may be stuck or very slow.")
        end
        println()
    end
    
    # Check if there are results
    results = get(data, "results_so_far", [])
    if !isempty(results)
        println("Latest Results:")
        for r in results
            println("  Threshold $(r.threshold) MPa:")
            println("    Inj rate: $(r.final_inj_rate)")
            println("    Objective: $(r.final_obj)")
            println("    POF: $(r.final_pof_smooth) (smooth), $(r.final_pof_hard) (hard)")
            println("    CVaR: $(r.final_cvar)")
        end
    end
    
    println("=" ^ 80)
end

main()

