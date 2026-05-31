# Lightweight script: inspect BHP vs reservoir pressure from saved JLD2.

using Pkg
Pkg.activate(".")
using JLD2
using Printf

function main()
    scratch_root = get(ENV, "SCRATCH", "/storage/home/hcoda1/6/$(ENV["USER"])/scratch")

    found_file = joinpath(scratch_root,
        "optim_injr_DT/DT_control/exp_name=step1",
        "POF__HARD__eps=0.05__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        "sample=64/j=0.jld2")

    println("Loading: $found_file")
    data = JLD2.load(found_file)

    BHP_arr = data["BHP_arr"]
    pres_arr = data["pres_arr"]

    n = (512, 1, 256)
    d = (6.25, 100.0, 6.25)
    x_idx = 250

    # Deduce inj_y: BHP[1] at first timestep ≈ hydrostatic at well top
    # p0(z) ≈ 9982 * z * d[3] (since h=0)
    bhp1_first = BHP_arr[1][1]
    approx_inj_y = round(Int, bhp1_first / 9982.0 / d[3])
    println("Estimated inj_y from BHP[1][1] = $(bhp1_first/1e6) MPa: ≈ z_index $approx_inj_y")

    # Find best matching z for BHP[1][1] by scanning nearby
    pres_2d_1 = pres_arr[1]
    best_z = approx_inj_y
    best_err = Inf
    for z_test in max(1, approx_inj_y-5):min(n[3], approx_inj_y+5)
        err = abs(pres_2d_1[x_idx, z_test] - bhp1_first)
        if err < best_err
            best_err = err
            best_z = z_test
        end
    end
    println("Best matching z-index for BHP[1][1]: z=$best_z (error=$(best_err/1e6) MPa)")

    inj_y = clamp(best_z, 191, 200)
    println("Using inj_y = $inj_y")

    bhp_len = length(BHP_arr[1])

    println("\n" * "=" ^ 70)
    println("BHP vs RESERVOIR PRESSURE COMPARISON (sample=64)")
    println("=" ^ 70)
    println("Well at x=$x_idx, z from $inj_y to $(inj_y + bhp_len - 1)")
    println("BHP vector length = $bhp_len")

    for ts_idx in [1, 10, 30, 60, 90, 120]
        if ts_idx < 1 || ts_idx > length(BHP_arr); continue; end
        bhp = BHP_arr[ts_idx]
        pres_2d = pres_arr[ts_idx]

        println("\n--- Timestep $ts_idx / $(length(BHP_arr)) ---")
        println(@sprintf("  %-5s  %-6s  %-16s  %-16s  %-16s  %-8s  %-16s",
                         "perf", "z_idx", "BHP (MPa)", "P_res (MPa)", "BHP-Pres (MPa)", "BHP<Pres?", "P_frac (MPa)"))
        println("  " * "-"^95)

        all_bhp_less = true
        for j in 1:bhp_len
            z_well = inj_y + j - 1
            if z_well >= 1 && z_well <= n[3]
                p_res = pres_2d[x_idx, z_well]
                diff = bhp[j] - p_res
                lt = bhp[j] < p_res
                if !lt; all_bhp_less = false; end
                p_frac = z_well * d[3] * 9982.0 + 4.0e6
                @printf("  %-5d  %-6d  %-16.6f  %-16.6f  %-+16.6f  %-8s  %-16.6f\n",
                        j, z_well, bhp[j]/1e6, p_res/1e6, diff/1e6,
                        lt ? "YES" : "NO", p_frac/1e6)
            end
        end
        println("  -> All BHP < reservoir pressure at well cells? ", all_bhp_less ? "YES" : "NO")
    end

    # BHP_bound_diff
    BHP_bd = data["BHP_bound_diff_arr"]
    println("\n\n" * "=" ^ 70)
    println("BHP_bound_diff_arr (= BHP_max - BHP, where BHP_max = p_max at well column)")
    println("=" ^ 70)
    for ts_idx in [1, 60, 120]
        if ts_idx < 1 || ts_idx > length(BHP_bd); continue; end
        println("\n  Timestep $ts_idx:")
        for (j, v) in enumerate(BHP_bd[ts_idx])
            @printf("    perf %d: bound_diff = %+.4f MPa (%s)\n", j, v/1e6, v > 0 ? "BHP < fracture" : "BHP >= fracture!")
        end
    end

    # Cross-check with sample=18
    println("\n\n" * "=" ^ 70)
    println("CROSS-CHECK: sample=18")
    println("=" ^ 70)
    found_file2 = joinpath(scratch_root,
        "optim_injr_DT/DT_control/exp_name=step1",
        "POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        "sample=18/j=0.jld2")
    data2 = JLD2.load(found_file2)
    BHP_arr2 = data2["BHP_arr"]
    pres_arr2 = data2["pres_arr"]

    bhp1_2 = BHP_arr2[1][1]
    approx_inj_y2 = round(Int, bhp1_2 / 9982.0 / d[3])
    inj_y2 = clamp(approx_inj_y2, 191, 200)
    println("Sample 18: estimated inj_y = $inj_y2, BHP length = $(length(BHP_arr2[1]))")

    for ts_idx in [1, length(BHP_arr2)]
        bhp = BHP_arr2[ts_idx]
        pres_2d = pres_arr2[ts_idx]
        println("\n--- Timestep $ts_idx ---")
        all_less = true
        for j in 1:length(bhp)
            z_well = inj_y2 + j - 1
            if z_well >= 1 && z_well <= n[3]
                p_res = pres_2d[x_idx, z_well]
                diff = bhp[j] - p_res
                lt = bhp[j] < p_res
                if !lt; all_less = false; end
                @printf("  perf %-2d  z=%-3d  BHP=%.4f  P_res=%.4f  diff=%-+.6f MPa  BHP<Pres? %s\n",
                        j, z_well, bhp[j]/1e6, p_res/1e6, diff/1e6, lt ? "YES" : "NO")
            end
        end
        println("  -> All BHP < reservoir pressure? ", all_less ? "YES" : "NO")
    end

    println("\nDone!")
end

main()
