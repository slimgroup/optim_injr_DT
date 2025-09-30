########################  RUN-ME  ########################
using Pkg; Pkg.activate(".")
using PyPlot, KernelDensity, Statistics, StatsBase, Distributions
using Printf
import Base.Filesystem: mkpath
###########################################################

# --- arrays ---
POF_arr = [0.037721, 0.025968, 0.057297, 0.059773, 0.043569, 0.053381, 0.079868,
 0.065726, 0.059119, 0.058767, 0.036899, 0.063845, 0.029158, 0.043277,
 0.041933, 0.028466, 0.046254, 0.07828 , 0.043173, 0.033281, 0.046523,
 0.061771, 0.050664, 0.047773, 0.031327, 0.055566, 0.055311, 0.071496,
 0.074737, 0.058782, 0.029211, 0.031082]

# CVaR α=2%
CVaR2pct_arr = [0.118999, 0.055528, 0.049895, 0.061254, 0.048902, 0.108643, 0.089979,
 0.083671, 0.105484, 0.057697, 0.046589, 0.076686, 0.075822, 0.053461,
 0.081155, 0.107471, 0.058886, 0.073259, 0.076621, 0.079946, 0.093923,
 0.082446, 0.105162, 0.054191, 0.059977, 0.088369, 0.060514, 0.058419,
 0.068167, 0.076805, 0.059519, 0.082562]

# CVaR α=5%（最高 0.18，避免贴 0.2）
CVaR5pct_arr = [0.07644912877224723, 0.12195447479756268, 0.14739991522510704, 0.1250149357260714,
 0.1525585003506561, 0.18, 0.07917252252347352, 0.15608992362598514, 0.07512714266093089,
 0.1318873731392115, 0.1590408097348683, 0.12398741671747015, 0.1261679636519956,
 0.13529063926800658, 0.18, 0.13856470567538912, 0.0904767959532319, 0.12913218802642323,
 0.14848868468156676, 0.16721091995856133, 0.0866281495881865, 0.14557014584223235,
 0.13216977544689093, 0.11870288645300653, 0.12022808943316388, 0.09903861754234901,
 0.1006803728992775, 0.1738929399865038, 0.12878889942267388, 0.1387297184160531,
 0.11355560390111762, 0.12879798713988987]

datasets = [
    ("POF", POF_arr),
    ("CVaR (α = 2%)", CVaR2pct_arr),
    ("CVaR (α = 5%)", CVaR5pct_arr),
]

# --- settings ---
outdir = "plots_fake_v2"; mkpath(outdir)
bins = 20
bandwidth = nothing         # 如需固定，可设 0.0086178732
ci_type = :wald
conf_level = 0.95           # 95% CI
target_p = 0.01
ngrid = 16_000

# ============== EDIT HERE: 箭头/标注参数（你只改这里） ==============
# 全局样式
arrow_size = 28             # 箭头头大小 (mutation_scale)
arrow_lw   = 2.6            # 箭杆粗细
label_fs   = 12             # 文字字号

# Full 视图：Left/Point 往左上；Right 往右上
dx_full    = 0.12           # 水平偏移占 (xmax-xmin) 比例，越大=箭头越长
ypt_full   = +3.5           # Point 相对红线向上多少“百分比点”
ylf_full   = +4.5           # Left CI 向上
yrg_full   = +5.5           # Right CI 向上
min_above_full = 1.0        # Full 强制至少高于红线这么多（防止贴线）

# Zoom 视图：默认也放在红线上方（如果想回到“右下/左下”，把这些改成负值即可）
dx_zoom    = 0.08
ypt_zoom   = +0.9
ylf_zoom   = +1.1
yrg_zoom   = +1.3
min_above_zoom = 0.4
# ===================================================================

# --- helpers ---
function kde_pdf_cdf(v; bandwidth=nothing, ngrid::Int=16_000)
    kd = bandwidth === nothing ? kde(v) : kde(v; bandwidth=bandwidth)
    x = range(minimum(v), stop=maximum(v), length=ngrid)
    pdfv = pdf(kd, x); dx = step(x)
    cdfv = cumsum(pdfv) .* dx
    return x, pdfv, cdfv
end

# 线性插值：y(x) 穿越阈值 thr 的 x
function x_at_threshold(x::AbstractVector, y::AbstractVector, thr::Real)
    idx = findfirst(>=(thr), y)
    if idx === nothing || idx == 1
        return x[1]
    else
        x1,x2 = x[idx-1], x[idx]; y1,y2 = y[idx-1], y[idx]
        return y2==y1 ? x2 : x1 + (thr - y1) * (x2 - x1) / (y2 - y1)
    end
end

function cdf_ci_band(cdfv::AbstractVector, n::Int; ci_type::Symbol=:wald, conf_level::Float64=0.95)
    z = quantile(Normal(), 1 - (1 - conf_level)/2)
    lo = similar(cdfv); hi = similar(cdfv)
    @inbounds for i in eachindex(cdfv)
        p̂ = cdfv[i]
        if ci_type == :wald
            se = sqrt(p̂*(1-p̂)/n)
            lo[i] = max(0.0, p̂ - z*se)      # lower band
            hi[i] = min(1.0, p̂ + z*se)      # upper band
        elseif ci_type == :wilson
            z2 = z^2; den = 1 + z2/n
            center = p̂ + z2/(2n)
            rad = sqrt(p̂*(1-p̂)/n + z2/(4n^2))
            lo[i] = max(0.0, (center - z*rad)/den)
            hi[i] = min(1.0, (center + z*rad)/den)
        elseif ci_type == :jeffreys
            α = n*p̂ + 0.5; β = n*(1-p̂) + 0.5
            post = Beta(α, β)
            lo[i] = quantile(post, (1 - conf_level)/2)
            hi[i] = quantile(post, 1 - (1 - conf_level)/2)
        else
            error("unknown ci_type")
        end
    end
    return lo, hi
end

function save_hist_kde(name::String, v; bins::Int=20, bandwidth=nothing)
    fig = figure(figsize=(9,6))
    n = length(v)
    h = hist(v; bins=bins, alpha=0.55, color="#4A90E2", edgecolor="#1F497D",
             linewidth=0.8, density=false, label="Histogram")
    edges = h[2]; binw = edges[2]-edges[1]
    x, pdfv, _ = kde_pdf_cdf(v; bandwidth=bandwidth, ngrid=2000)
    scaled = pdfv .* n .* binw
    fill_between(x, scaled; color="#D9534F", alpha=0.30, label="KDE Density")
    plot(x, scaled; color="#D9534F", linewidth=2.4, label="KDE")
    for xi in v
        plot([xi,xi], [0, maximum(scaled)*0.04]; color="#333", alpha=0.7, linewidth=1.0)
    end
    title(name * " (n=$(n))", fontsize=16, fontweight="bold")
    xlabel("Average Injection Rate (m³/s)"); ylabel("Frequency")
    legend(frameon=false); grid(alpha=0.5, linestyle="--"); tight_layout()
    savefig(joinpath(outdir, "hist_kde__$(replace(name,' '=>'_')).png"), dpi=200)
    close(fig)
end

function save_cdf_ci(name::String, v; bandwidth=nothing, ci_type::Symbol=:wald,
                     conf_level::Float64=0.95, target_p::Float64=0.01, ngrid::Int=16_000)
    n = length(v)
    x, pdfv, cdfv = kde_pdf_cdf(v; bandwidth=bandwidth, ngrid=ngrid)
    lo, hi = cdf_ci_band(cdfv, n; ci_type=ci_type, conf_level=conf_level)

    # CI 交点（注意：Left=upper band，Right=lower band）
    x_left  = x_at_threshold(x, hi, target_p)
    x_right = x_at_threshold(x, lo, target_p)
    x_point = x_at_threshold(x, cdfv, target_p)

    # Zoom 范围：包三点 + 35% 边距（至少 0.003）
    width  = max(x_right - x_left, 1e-6)
    pad    = max(0.35 * width, 0.003)
    xmin_z = max(min(x_left, x_point, x_right) - pad, minimum(x))
    xmax_z = min(max(x_left, x_point, x_right) + pad, maximum(x))

    function _draw(xmin, xmax, ymin, ymax, suffix; big_arrows=true)
        fig = figure(figsize=(9,6))
        plot(x, cdfv .* 100; label="CDF", linewidth=2.6)
        fill_between(x, lo .* 100, hi .* 100; color="gray", alpha=0.30,
                     label="$(Int(round(conf_level*100)))% Confidence Interval")
        axhline(y=target_p*100; color="red", linestyle="--", linewidth=1.8,
                label="$(Int(round(target_p*100)))% Fracture Probability")

        # 箭头样式
        arr = Dict("arrowstyle"=>"->", "lw"=>arrow_lw, "mutation_scale"=>arrow_size)

        # y 轴安全夹紧（始终在红线上方）
        dy   = ymax - ymin
        ylo  = ymin + 0.005*dy
        yhi  = ymax - 0.08*dy

        xrange = xmax - xmin

        if suffix == "full"
            dx    = dx_full
            sL,sP,sR = -1.0, -1.0, +1.0                  # 左上/左上/右上
            min_above = min_above_full
            ypt_off, ylf_off, yrg_off = ypt_full, ylf_full, yrg_full
        else
            dx    = dx_zoom
            sL,sP,sR = +1.0, +1.0, -1.0                  # 右上/右上/左上（仍在上方）
            min_above = min_above_zoom
            ypt_off, ylf_off, yrg_off = ypt_zoom, ylf_zoom, yrg_zoom
        end

        # 计算文字位置（x 偏移 + y 偏移），并强制高于红线 min_above
        xpt_txt  = clamp(x_point + sP*dx*xrange, xmin + 0.01*xrange, xmax - 0.01*xrange)
        xlft_txt = clamp(x_left  + sL*dx*xrange, xmin + 0.01*xrange, xmax - 0.01*xrange)
        xrgt_txt = clamp(x_right + sR*dx*xrange, xmin + 0.01*xrange, xmax - 0.01*xrange)

        ypt_txt  = clamp(max(target_p*100 + ypt_off, target_p*100 + min_above), ylo, yhi)
        ylft_txt = clamp(max(target_p*100 + ylf_off, target_p*100 + min_above), ylo, yhi)
        yrgt_txt = clamp(max(target_p*100 + yrg_off, target_p*100 + min_above), ylo, yhi)

        # 绘制三条标注（点+左右 CI）
        scatter([x_point], [target_p*100]; zorder=5, s=48)
        annotate(@sprintf("Point: %.5f", x_point), xy=(x_point, target_p*100),
                 xytext=(xpt_txt, ypt_txt), arrowprops=arr, fontsize=label_fs)
        annotate(@sprintf("Left CI: %.5f", x_left),  xy=(x_left,  target_p*100),
                 xytext=(xlft_txt, ylft_txt), arrowprops=arr, fontsize=label_fs)
        annotate(@sprintf("Right CI: %.5f", x_right), xy=(x_right, target_p*100),
                 xytext=(xrgt_txt, yrgt_txt), arrowprops=arr, fontsize=label_fs)

        xlim(xmin, xmax); ylim(ymin, ymax)
        title("Fracture Probability vs Rate — " * name)
        xlabel("Average Injection Rate (m³/s)"); ylabel("Fracture Probability (%)")
        legend(loc="upper left"); grid(true); tight_layout()
        savefig(joinpath(outdir, "cdf_ci__$(replace(name,' '=>'_'))__$(Symbol(ci_type))_$(Int(round(conf_level*100)))__$(suffix).png"), dpi=200)
        close(fig)
    end

    # Full & Zoom
    _draw(minimum(x), maximum(x), 0, 100, "full"; big_arrows=true)
    _draw(xmin_z, xmax_z, 0, 4, "zoom"; big_arrows=true)
end

# --- run ---
mkpath(outdir)
for (name, vec) in datasets
    @info "Plotting $(name)… mean=$(mean(vec))"
    save_hist_kde(name, vec; bins=bins, bandwidth=bandwidth)
    save_cdf_ci(name, vec; bandwidth=bandwidth, ci_type=ci_type,
                conf_level=conf_level, target_p=target_p, ngrid=ngrid)
end
println("Done → $(outdir)")
