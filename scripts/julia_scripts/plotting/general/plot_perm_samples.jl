# Script to generate multi-panel permeability samples figure for paper
# Shows 3 representative permeability realizations from the ensemble

using JLD2
using PyPlot
using Random
using Dates

# ─────────────────────────────────────────────────────────────────────────────
# Domain parameters (from optim_inject.jl)
n = (512, 1, 256)
d = (6.25, 100.0, 6.25)
h = 0.0

# millidarcy constant (from JutulDarcyRules)
md = 9.869232667160131e-16

# ─────────────────────────────────────────────────────────────────────────────
# Paths
base_path = dirname(dirname(@__FILE__))
data_path = joinpath(base_path, "data")
plots_path = joinpath(base_path, "plots", "DT_control", "exp_name=step1")
mkpath(plots_path)

# Load permeability data
perm_path = joinpath(data_path, "geo/wise_perm_models_2000_new.jld2")
perm_data = JLD2.load(perm_path)
BroadK = perm_data["BroadK"]

# Load monitoring step 1 indices
monitoring_step = 1
state_path = joinpath(data_path, "state/Wise128_state_t$(monitoring_step)_rtm1_broad_NL_SNR28.jld2")
state_data = JLD2.load(state_path)
indices = state_data["idx_t$(monitoring_step)"]

println("Number of samples in monitoring step 1: ", length(indices))
println("Indices range: ", minimum(indices), " to ", maximum(indices))

# ─────────────────────────────────────────────────────────────────────────────
# Randomly select 3 samples
Random.seed!(2025)  # For reproducibility
selected_samples = sort(rand(1:length(indices), 3))  # 3 random sample indices (1-based into indices array)
selected_perm_indices = indices[selected_samples]  # Actual indices into BroadK

println("Selected sample indices: ", selected_samples)
println("Corresponding permeability indices: ", selected_perm_indices)

# ─────────────────────────────────────────────────────────────────────────────
# Create multi-panel figure
rc("font", family="serif")
rc("xtick", labelsize=12)
rc("ytick", labelsize=12)

fig, axes = subplots(1, 3, figsize=(15, 4), sharey=true)
im_ratio = n[3] * d[3] / (n[1] * d[1])

for (panel_idx, (sample_idx, perm_idx)) in enumerate(zip(selected_samples, selected_perm_indices))
    K = BroadK[perm_idx, :, :] * md
    logK = log10.(transpose(K / md))
    
    ax = axes[panel_idx]
    im = ax.imshow(logK, vmin=0, vmax=4, 
                   extent=(0, (n[1]-1)*d[1], h+(n[3]-1)*d[3], h), 
                   cmap="cet_rainbow4")
    
    ax.set_title("Realization $(sample_idx)", fontsize=14)
    ax.set_xlabel("X [m]", fontsize=12)
    if panel_idx == 1
        ax.set_ylabel("Depth [m]", fontsize=12)
    end
end

# Add single colorbar for all panels
fig.subplots_adjust(right=0.92, wspace=0.08)
cbar_ax = fig.add_axes([0.93, 0.15, 0.015, 0.7])
clb = fig.colorbar(axes[end].images[1], cax=cbar_ax)
clb.ax.set_title("log₁₀(K)\n[mD]", fontsize=11, pad=8)
clb.set_ticks(log10.([1, 10, 100, 1000]))
clb.set_ticklabels(["1", "10", "100", "1000"])

# Save figure
timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
filename = joinpath(plots_path, "permeability_samples_$(timestamp).png")
savefig(filename, dpi=300, bbox_inches="tight")
println("Saved figure to: ", filename)

# Also save a PDF version for paper
filename_pdf = joinpath(plots_path, "permeability_samples_$(timestamp).pdf")
savefig(filename_pdf, dpi=300, bbox_inches="tight")
println("Saved PDF to: ", filename_pdf)

close(fig)
println("Done!")
