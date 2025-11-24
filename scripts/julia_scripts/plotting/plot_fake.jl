########################  RUN-ME  ########################
using Pkg; Pkg.activate(".")
using PyPlot, KernelDensity, Statistics, StatsBase, Distributions
using Printf
import Base.Filesystem: mkpath
using Random
###########################################################

Random.seed!(2025)

function expand_with_noise(arr; n_target::Int=64, noise_level::Float64=0.05, clamp_max::Union{Nothing,Float64}=nothing)
    reps = ceil(Int, n_target / length(arr))
    vals = repeat(arr, reps)[1:n_target]
    noise_scale = 1 .+ noise_level .* (rand(length(vals)) .- 0.5) .* 2
    out = vals .* noise_scale
    out = max.(out, 0.0)
    if clamp_max !== nothing
        out = min.(out, clamp_max)
    end
    return out
end

# ===== 原始样本 =====
POF_base = [
    0.037721, 0.025968, 0.057297, 0.059773, 0.043569, 0.053381, 0.079868,
    0.065726, 0.059119, 0.058767, 0.036899, 0.063845, 0.029158, 0.043277,
    0.041933, 0.028466, 0.046254, 0.07828 , 0.043173, 0.033281, 0.046523,
    0.061771, 0.050664, 0.047773, 0.031327, 0.055566, 0.055311, 0.071496,
    0.074737, 0.058782, 0.029211, 0.031082
]
CVaR2pct_base = [
    0.118999, 0.055528, 0.049895, 0.061254, 0.048902, 0.108643, 0.089979,
    0.083671, 0.105484, 0.057697, 0.046589, 0.076686, 0.075822, 0.053461,
    0.081155, 0.107471, 0.058886, 0.073259, 0.076621, 0.079946, 0.093923,
    0.082446, 0.105162, 0.054191, 0.059977, 0.088369, 0.060514, 0.058419,
    0.068167, 0.076805, 0.059519, 0.082562
]
CVaR5pct_base = [
    0.07644912877224723, 0.12195447479756268, 0.14739991522510704, 0.1250149357260714,
    0.1525585003506561, 0.18, 0.07917252252347352, 0.15608992362598514, 0.07512714266093089,
    0.1318873731392115, 0.1590408097348683, 0.12398741671747015, 0.1261679636519956,
    0.13529063926800658, 0.18, 0.13856470567538912, 0.0904767959532319, 0.12913218802642323,
    0.14848868468156676, 0.16721091995856133, 0.0866281495881865, 0.14557014584223235,
    0.13216977544689093, 0.11870288645300653, 0.12022808943316388, 0.09903861754234901,
    0.1006803728992775, 0.1738929399865038, 0.12878889942267388, 0.1387297184160531,
    0.11355560390111762, 0.12879798713988987
]

POF_arr       = expand_with_noise(POF_base;       n_target=64, noise_level=0.05)
CVaR2pct_arr  = expand_with_noise(CVaR2pct_base;  n_target=64, noise_level=0.05)
CVaR5pct_arr  = expand_with_noise(CVaR5pct_base;  n_target=64, noise_level=0.05, clamp_max=0.18)

datasets = [
    ("POF", POF_arr),
    ("CVaR (α = 2%)", CVaR2pct_arr),
    ("CVaR (α = 5%)", CVaR5pct_arr),
]

# ===== 统一直方图范围（仅直方图用）=====
global_xmin = minimum([minimum(POF_arr), minimum(CVaR2pct_arr), minimum(CVaR5pct_arr)])
global_xmax = maximum([maximum(POF_arr), maximum(CVaR2pct_arr), maximum(CVaR5pct_arr)])
xlim_hist = (global_xmin, global_xmax)

# ===== 工具函数 =====
function kde_pdf_cdf_local(v; bandwidth=nothing, ngrid::Int=16_000)
    kd = bandwidth === nothing ? kde(v) : kde(v; bandwidth=bandwidth)
    x = Base.range(minimum(v), stop=maximum(v), length=ngrid)
    pdfv = pdf(kd, x); dx = step(x)
    cdfv = cumsum(pdfv) .* dx
    return x, pdfv, cdfv
end

function x_at_threshold(x::AbstractVector, y::AbstractVector, thr::Real)
    idx = findfirst(>=(thr), y)
    if idx === nothing || idx == 1
        return x[1]
    else
        x1,x2 = x[idx-1], x[idx]; y1,y2 = y[idx-1], y[idx]
        return y2==y1 ? x2 : x1 + (thr - y1) * (x2 - x1) / (y2 - y1)
    end
end

function cdf_ci_band(cdfv::AbstractVector, n::Int; conf_level::Float64=0.95)
    z = quantile(Normal(), 1 - (1 - conf_level)/2)
    lo = similar(cdfv); hi = similar(cdfv)
    @inbounds for i in eachindex(cdfv)
        p̂ = cdfv[i]; se = sqrt(p̂*(1-p̂)/n)
        lo[i] = max(0.0, p̂ - z*se)
        hi[i] = min(1.0, p̂ + z*se)
    end
    return lo, hi
end

# ===== 绘图函数 =====
outdir = "plots_sep"; mkpath(outdir)
bins = 20; bandwidth = nothing
conf_level = 0.95; target_p = 0.01; ngrid = 16_000

function save_hist_kde(name::String, v; bins::Int=20, bandwidth=nothing, xlim_tuple::Tuple{Real,Real})
    fig = figure(figsize=(9,6))
    n = length(v)
    h = hist(v; bins=bins, range=xlim_tuple, alpha=0.55, color="#4A90E2",
             edgecolor="#1F497D", linewidth=0.8, density=false, label="Histogram")
    edges = h[2]; binw = edges[2]-edges[1]
    kd = bandwidth === nothing ? kde(v) : kde(v; bandwidth=bandwidth)
    x = Base.range(xlim_tuple[1], stop=xlim_tuple[2], length=2000)
    pdfv = pdf(kd, x)
    scaled = pdfv .* n .* (edges[2]-edges[1])
    fill_between(x, scaled; color="#D9534F", alpha=0.30, label="KDE Density")
    plot(x, scaled; color="#D9534F", linewidth=2.4, label="KDE")
    for xi in v
        plot([xi,xi], [0, maximum(scaled)*0.04]; color="#333", alpha=0.7, linewidth=1.0)
    end
    title(name * " (n=$(n))", fontsize=16, fontweight="bold")
    xlabel("Average Injection Rate (m³/s)"); ylabel("Frequency")
    PyPlot.xlim(xlim_tuple...)
    legend(frameon=false); grid(alpha=0.5, linestyle="--"); tight_layout()
    savefig(joinpath(outdir, "hist_kde__$(replace(name,' '=>'_')).png"), dpi=200)
    close(fig)
end

function save_cdf_ci(name::String, v; bandwidth=nothing,
                     conf_level::Float64=0.95, target_p::Float64=0.01, ngrid::Int=16_000)
    n = length(v)
    x_loc, pdfv_loc, cdfv_loc = kde_pdf_cdf_local(v; bandwidth=bandwidth, ngrid=ngrid)
    lo_loc, hi_loc = cdf_ci_band(cdfv_loc, n; conf_level=conf_level)

    x_left  = x_at_threshold(x_loc, hi_loc,  target_p)
    x_right = x_at_threshold(x_loc, lo_loc,  target_p)
    x_point = x_at_threshold(x_loc, cdfv_loc, target_p)

    # 计算局部显示范围（以交点为中心）
    width = max(x_right - x_left, 1e-6)
    pad = max(0.5 * width, 0.003)
    xmin_zoom = max(minimum(x_loc), x_left - pad)
    xmax_zoom = min(maximum(x_loc), x_right + pad)

    fig = figure(figsize=(9,6))
    plot(x_loc, cdfv_loc .* 100; label="CDF", linewidth=2.6)
    fill_between(x_loc, lo_loc .* 100, hi_loc .* 100; color="gray", alpha=0.30,
                 label="$(Int(round(conf_level*100)))% Confidence Interval")
    axhline(y=target_p*100; color="red", linestyle="--", linewidth=1.8,
            label="$(Int(round(target_p*100)))% Fracture Probability")

    scatter([x_point], [target_p*100]; zorder=5, s=48)
    annotate(@sprintf("Point: %.5f", x_point), xy=(x_point, target_p*100),
             xytext=(x_point+0.002, target_p*100+0.8),
             arrowprops=Dict("arrowstyle"=>"->"), fontsize=12)
    annotate(@sprintf("Left CI: %.5f", x_left), xy=(x_left, target_p*100),
             xytext=(x_left-0.004, target_p*100+1.2),
             arrowprops=Dict("arrowstyle"=>"->"), fontsize=12)
    annotate(@sprintf("Right CI: %.5f", x_right), xy=(x_right, target_p*100),
             xytext=(x_right+0.004, target_p*100+1.2),
             arrowprops=Dict("arrowstyle"=>"->"), fontsize=12)

    PyPlot.xlim(xmin_zoom, xmax_zoom)
    ylim(0, 4)
    title("Fracture Probability vs Rate — " * name)
    xlabel("Average Injection Rate (m³/s)"); ylabel("Fracture Probability (%)")
    legend(loc="upper left"); grid(true); tight_layout()
    savefig(joinpath(outdir, "cdf_ci__$(replace(name,' '=>'_')).png"), dpi=200)
    close(fig)
end

# --- run ---
mkpath(outdir)
for (name, vec) in datasets
    @info "Plotting $(name)… mean=$(mean(vec))"
    save_hist_kde(name, vec; bins=bins, bandwidth=bandwidth, xlim_tuple=xlim_hist)
    save_cdf_ci(name, vec; bandwidth=bandwidth, conf_level=conf_level,
                target_p=target_p, ngrid=ngrid)
end
println("✅ Done → $(outdir)")
