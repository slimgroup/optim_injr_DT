using Pkg
Pkg.activate(".")
using JLD2
using Printf

function main()
    scratch_root = get(ENV, "SCRATCH", "/storage/home/hcoda1/6/$(ENV["USER"])/scratch")

    f64 = joinpath(scratch_root,
        "optim_injr_DT/DT_control/exp_name=step1",
        "POF__HARD__eps=0.05__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        "sample=64/j=0.jld2")

    println("Loading sample=64 data...")
    data = JLD2.load(f64)
    BHP_arr = data["BHP_arr"]
    pres_arr = data["pres_arr"]

    n = (512, 1, 256)
    d = (6.25, 100.0, 6.25)
    x_idx = 250

    bhp1 = BHP_arr[1][1]
    inj_y = clamp(round(Int, bhp1 / 9982.0 / d[3]), 191, 200)
    bhp_len = length(BHP_arr[1])
    well_z_range = inj_y:(inj_y + bhp_len - 1)
    println("Well: x=$x_idx, z=$inj_y to $(inj_y+bhp_len-1)")

    println("\n" * "=" ^ 70)
    println("WHERE IS MAX RESERVOIR PRESSURE? (sample=64)")
    println("=" ^ 70)

    for ts_idx in [1, 10, 30, 60, 90, 120]
        if ts_idx > length(pres_arr); continue; end
        pres_2d = pres_arr[ts_idx]
        gmax = maximum(pres_2d)
        gidx = argmax(pres_2d)
        gx, gz = gidx[1], gidx[2]
        is_at_well = (gx == x_idx && gz in well_z_range)
        well_pres = [pres_2d[x_idx, z] for z in well_z_range]
        wmax = maximum(well_pres)

        flat = vec(pres_2d)
        top5_idx = partialsortperm(flat, 1:5, rev=true)
        top5_coords = [(mod1(i, n[1]), div(i-1, n[1])+1) for i in top5_idx]
        top5_vals = flat[top5_idx]

        println("\n--- Timestep $ts_idx ---")
        @printf("  Global max P = %.4f MPa at (x=%d, z=%d)%s\n",
                gmax/1e6, gx, gz, is_at_well ? " *** AT WELL ***" : "")
        @printf("  Well max P   = %.4f MPa\n", wmax/1e6)
        @printf("  Gap          = %.4f MPa\n", (gmax - wmax)/1e6)
        println("  Top 5 pressure locations:")
        for k in 1:5
            cx, cz = top5_coords[k]
            aw = (cx == x_idx && cz in well_z_range) ? " [WELL]" : ""
            @printf("    #%d: %.4f MPa at (x=%d, z=%d)%s\n", k, top5_vals[k]/1e6, cx, cz, aw)
        end
        top100_idx = partialsortperm(flat, 1:100, rev=true)
        n_at_well = count(i -> (mod1(i,n[1])==x_idx && div(i-1,n[1])+1 in well_z_range), top100_idx)
        println("  Of top-100 highest P cells: $n_at_well at well")
    end

    println("\n\n" * "=" ^ 70)
    println("BHP vs P_res SUMMARY (sample=64)")
    println("=" ^ 70)
    ng = 0; nl = 0; nt = 0
    for ts in 1:length(BHP_arr)
        bhp = BHP_arr[ts]; pres_2d = pres_arr[ts]
        for j in 1:bhp_len
            nt += 1
            if bhp[j] > pres_2d[x_idx, inj_y+j-1]; ng += 1; else; nl += 1; end
        end
    end
    @printf("BHP > P_res: %d / %d (%.1f%%)\n", ng, nt, 100.0*ng/nt)
    @printf("BHP <= P_res: %d / %d (%.1f%%)\n", nl, nt, 100.0*nl/nt)

    println("\nPer-timestep:")
    for ts in [1,5,10,15,20,30,40,50,60,80,100,120]
        if ts > length(BHP_arr); continue; end
        bhp = BHP_arr[ts]; pres_2d = pres_arr[ts]
        cnt = sum(bhp[j] > pres_2d[x_idx, inj_y+j-1] for j in 1:bhp_len)
        println("  ts=$ts: $cnt/8 perfs have BHP > P_res")
    end

    println("\n\n" * "=" ^ 70)
    println("SAMPLE=18: MAX PRESSURE LOCATION")
    println("=" ^ 70)
    f18 = joinpath(scratch_root,
        "optim_injr_DT/DT_control/exp_name=step1",
        "POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        "sample=18/j=0.jld2")
    data2 = JLD2.load(f18)
    pres_arr2 = data2["pres_arr"]
    BHP_arr2 = data2["BHP_arr"]
    bhp1_2 = BHP_arr2[1][1]
    inj_y2 = clamp(round(Int, bhp1_2 / 9982.0 / d[3]), 191, 200)
    well_z2 = inj_y2:(inj_y2 + length(BHP_arr2[1]) - 1)
    println("Sample 18: inj_y=$inj_y2, well z=$well_z2")

    for ts_idx in [1, 60, 120]
        if ts_idx > length(pres_arr2); continue; end
        pres_2d = pres_arr2[ts_idx]
        gmax = maximum(pres_2d)
        gidx = argmax(pres_2d)
        gx, gz = gidx[1], gidx[2]
        is_well = (gx == x_idx && gz in well_z2)
        wmax = maximum([pres_2d[x_idx, z] for z in well_z2])

        flat = vec(pres_2d)
        top5_idx = partialsortperm(flat, 1:5, rev=true)
        top5c = [(mod1(i, n[1]), div(i-1, n[1])+1) for i in top5_idx]
        top5v = flat[top5_idx]

        @printf("\n  ts=%3d: Global max=%.4f MPa at (x=%d,z=%d)%s, Well max=%.4f MPa\n",
                ts_idx, gmax/1e6, gx, gz, is_well ? " [WELL]" : "", wmax/1e6)
        for k in 1:5
            cx, cz = top5c[k]
            aw = (cx == x_idx && cz in well_z2) ? " [WELL]" : ""
            @printf("    #%d: %.4f MPa at (x=%d,z=%d)%s\n", k, top5v[k]/1e6, cx, cz, aw)
        end
    end

    println("\nDone!")
end

main()
