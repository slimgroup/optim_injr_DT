# Activate the project environment
using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"
using JLD2

@load "scripts/max_three_val_frac_pres_k1_new.jld2"

jtp_min_three = 4 * 10^6 .- jtp_max_three
rtp_min_three = 4 * 10^6 .- rtp_max_three

using PyPlot
using KernelDensity

function plot_row_comparison(hf_mat, lf_mat, row_idx, outname)
    hf_row = hf_mat[row_idx, :]
    lf_row = lf_mat[row_idx, :]
    kde_hf = kde(hf_row)
    kde_lf = kde(lf_row)

    figure(figsize=(10, 6))

    # Joint distribution (former HF)
    hist(hf_row, bins=30, density=true, alpha=0.3, label="Joint Histogram", color="blue")
    plot(kde_hf.x, kde_hf.density, label="Joint KDE", color="blue", linewidth=2)

    # Reference distribution (former LF)
    hist(lf_row, bins=30, density=true, alpha=0.3, label="Reference Histogram", color="orange")
    plot(kde_lf.x, kde_lf.density, label="Reference KDE", color="orange", linestyle="--", linewidth=2)

    xlabel("Pressure")
    ylabel("Density")
    ordinal = ["1st", "2nd", "3rd"]
    title("Distribution of the $(ordinal[row_idx]) Minimum Pressure Difference (Joint vs Reference)")
    legend()
    grid(true)
    tight_layout()
    savefig(outname, dpi=300)
end

# 绘制 1st, 2nd, 3rd 最小压力分布
plot_row_comparison(jtp_min_three, rtp_min_three, 1, "min_pressure_row1.png")
plot_row_comparison(jtp_min_three, rtp_min_three, 2, "min_pressure_row2.png")
plot_row_comparison(jtp_min_three, rtp_min_three, 3, "min_pressure_row3.png")
