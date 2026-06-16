using JLD2
using Printf

function main()
    scratch_root = get(ENV, "SCRATCH", joinpath(homedir(), "scratch"))

    # Load both samples
    f64 = joinpath(scratch_root,
        "optim_injr_DT/DT_control/exp_name=step1",
        "POF__HARD__eps=0.05__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        "sample=64/j=0.jld2")
    f18 = joinpath(scratch_root,
        "optim_injr_DT/DT_control/exp_name=step1",
        "POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        "sample=18/j=0.jld2")

    n = (512, 1, 256)
    d = (6.25, 100.0, 6.25)
    x_idx = 250
    ds = 10
    forward_step = 2
    inj_start = 0.0001

    for (label, fpath) in [("sample=64 (POF eps=0.05)", f64), ("sample=18 (POF eps=0.01)", f18)]
        println("\n" * "=" ^ 80)
        println("  $label")
        println("=" ^ 80)

        data = JLD2.load(fpath)
        BHP_arr = data["BHP_arr"]
        pres_arr = data["pres_arr"]

        bhp1 = BHP_arr[1][1]
        inj_y = clamp(round(Int, bhp1 / 9982.0 / d[3]), 191, 200)
        bhp_len = length(BHP_arr[1])
        well_z = inj_y:(inj_y + bhp_len - 1)
        n_ts = length(BHP_arr)

        # Reconstruct injection rate ramp
        # From optim_inject.jl: inj_rate = collect(range(inj_start, inj_rate[1], forward_step * 6))
        # Each block has ds=10 timesteps, total = forward_step*6 = 12 blocks, 120 timesteps
        # We don't know the final inj_rate, but we can infer the block index
        println("Well: x=$x_idx, z=$inj_y to $(inj_y+bhp_len-1), $bhp_len perforations")
        println("Total timesteps: $n_ts")

        # ──────────────────────────────────────────────────────────────────
        # ANALYSIS 1: BHP vs P_res at each perforation, every timestep
        # ──────────────────────────────────────────────────────────────────
        println("\n--- BHP vs P_res: per-timestep summary ---")
        println(@sprintf("  %-4s  %-8s  %-12s  %-12s  %-12s  %-12s  %-20s",
                "ts", "#BHP>Pr", "min(BHP-Pr)", "max(BHP-Pr)", "avg(BHP-Pr)", "BHP[1]-Pr[1]", "status"))

        transition_ts = -1
        for ts in 1:n_ts
            bhp = BHP_arr[ts]
            pres_2d = pres_arr[ts]
            diffs = [bhp[j] - pres_2d[x_idx, inj_y+j-1] for j in 1:bhp_len]
            n_pos = count(d -> d > 0, diffs)
            status = n_pos == bhp_len ? "ALL inject" :
                     n_pos == 0 ? "NONE inject" :
                     "$n_pos inject, $(bhp_len-n_pos) backflow"
            if n_pos == bhp_len && transition_ts < 0
                transition_ts = ts
            end

            if ts <= 15 || ts % 10 == 0 || ts == n_ts
                @printf("  %-4d  %-8d  %+12.4f  %+12.4f  %+12.4f  %+12.4f  %-20s\n",
                        ts, n_pos,
                        minimum(diffs)/1e6, maximum(diffs)/1e6,
                        sum(diffs)/length(diffs)/1e6,
                        diffs[1]/1e6, status)
            end
        end
        if transition_ts > 0
            println("  >>> Transition to ALL perfs injecting at timestep $transition_ts")
        else
            println("  >>> NOT all perfs injecting even at final timestep")
        end

        # ──────────────────────────────────────────────────────────────────
        # ANALYSIS 2: Where is max P_res? At well or elsewhere?
        # ──────────────────────────────────────────────────────────────────
        println("\n--- Max reservoir pressure location ---")
        println(@sprintf("  %-4s  %-14s  %-20s  %-14s  %-14s  %-10s",
                "ts", "Global max MPa", "Location (x,z)", "Well max MPa", "Gap MPa", "At well?"))

        n_at_well = 0
        for ts in 1:n_ts
            pres_2d = pres_arr[ts]
            gmax = maximum(pres_2d)
            gidx = argmax(pres_2d)
            gx, gz = gidx[1], gidx[2]
            is_well = (gx == x_idx && gz in well_z)
            if is_well; n_at_well += 1; end
            wmax = maximum(pres_2d[x_idx, z] for z in well_z)
            gap = gmax - wmax

            if ts <= 5 || ts % 10 == 0 || ts == n_ts || is_well
                @printf("  %-4d  %-14.4f  (x=%-3d, z=%-3d)      %-14.4f  %-14.4f  %-10s\n",
                        ts, gmax/1e6, gx, gz, wmax/1e6, gap/1e6, is_well ? "YES ***" : "no")
            end
        end
        println("  >>> Global max at well: $n_at_well / $n_ts timesteps")

        # ──────────────────────────────────────────────────────────────────
        # ANALYSIS 3: Rank of well grid points among ALL grid points
        # ──────────────────────────────────────────────────────────────────
        println("\n--- Well grid points: percentile rank in reservoir pressure ---")
        total_cells = n[1] * n[3]
        for ts in [1, 30, 60, 90, n_ts]
            if ts > n_ts; continue; end
            pres_2d = pres_arr[ts]
            flat = vec(pres_2d)
            sorted_desc = sort(flat, rev=true)

            well_pres_vals = [pres_2d[x_idx, z] for z in well_z]
            best_well_val = maximum(well_pres_vals)
            rank_best = findfirst(x -> x <= best_well_val, sorted_desc)
            pctile = 100.0 * (1.0 - rank_best / total_cells)

            worst_well_val = minimum(well_pres_vals)
            rank_worst = findfirst(x -> x <= worst_well_val, sorted_desc)
            pctile_worst = 100.0 * (1.0 - rank_worst / total_cells)

            @printf("  ts=%3d: well max P=%.4f MPa (rank %d/%d, top %.1f%%), well min P=%.4f MPa (top %.1f%%)\n",
                    ts, best_well_val/1e6, rank_best, total_cells, 100.0*rank_best/total_cells,
                    worst_well_val/1e6, 100.0*rank_worst/total_cells)
        end

        # ──────────────────────────────────────────────────────────────────
        # ANALYSIS 4: Among cells NEAR the well (same depth range), where is max?
        # ──────────────────────────────────────────────────────────────────
        println("\n--- Pressure at well depth range: well column vs neighbors ---")
        for ts in [1, 30, 60, 90, n_ts]
            if ts > n_ts; continue; end
            pres_2d = pres_arr[ts]

            println("\n  ts=$ts:")
            for z in well_z
                p_well = pres_2d[x_idx, z]
                # Check nearby x columns at the same z
                nearby_x = max(1, x_idx-20):min(n[1], x_idx+20)
                p_max_row = maximum(pres_2d[x, z] for x in nearby_x)
                x_of_max = argmax([pres_2d[x, z] for x in nearby_x])
                x_max_actual = collect(nearby_x)[x_of_max]
                is_well_max = (x_max_actual == x_idx)

                @printf("    z=%3d: P_well=%.4f, P_max_nearby=%.4f at x=%d %s\n",
                        z, p_well/1e6, p_max_row/1e6, x_max_actual,
                        is_well_max ? "(WELL is max)" : "(neighbor is max)")
            end
        end
    end

    println("\n\nDone!")
end

main()
