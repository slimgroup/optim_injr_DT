using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2, PyPlot, Printf
using Statistics   # Can also use StatsBase if needed

"""
load_final(path) -> Dict
  Returns a dictionary containing inj_rate_arr, step_arr, stp_cause, stp_alpha_ratio, etc.
"""
function load_final(path::AbstractString)
    @assert isfile(path) "No file: $path"
    data = JLD2.load(path)
    return data
end

"""
get_inj_curve(data) -> (iters, inj_vec)
  Extracts injection rate for each iteration (assuming single control variable), length = niterations+1
"""
function get_inj_curve(data)
    inj = data["inj_rate_arr"][:, 1]
    iters = collect(0:length(inj)-1)
    return iters, inj
end

"""
print_cause_stats!(label, data)
"""
function print_cause_stats!(label::AbstractString, data)
    cause = get(data, "stp_cause", Int[])
    n  = length(cause)
    n1 = count(==(1), cause)
    n2 = count(==(2), cause)
    n0 = n - n1 - n2
    println("[$label] stp_cause counts: 1(Feasibility)=$n1, 2(Armijo)=$n2, 0(Other)=$n0, total recorded=$n")
    if haskey(data, "stp_alpha_ratio")
        r = data["stp_alpha_ratio"]
        if !isempty(r)
            @printf("[%s] median alpha_ratio=%.2f, max=%.2f\n", label, median(r), maximum(r))
        end
    end
end

"""
plot_two_cases(file_a, label_a, file_b, label_b; out="inj_compare.png")
"""
function plot_two_cases(file_a::AbstractString, label_a::AbstractString,
                        file_b::AbstractString, label_b::AbstractString;
                        out::AbstractString="inj_compare.png")

    A = load_final(file_a); B = load_final(file_b)

    # 1) stats
    print_cause_stats!(label_a, A)
    print_cause_stats!(label_b, B)

    # 2) injection rate curves
    itA, injA = get_inj_curve(A)
    itB, injB = get_inj_curve(B)

    figure(figsize=(6,4))
    plot(itA, injA, "-o", label=label_a)
    plot(itB, injB, "-s", label=label_b)
    xlabel("iteration"); ylabel("injection rate")
    title("Injection rate vs iteration")
    legend(); tight_layout()
    savefig(out, dpi=180); close()
    println("Saved: $(out)")

    # 3) stp_cause timeline (0/1/2)
    causeA = get(A, "stp_cause", Int[])
    causeB = get(B, "stp_cause", Int[])
    len = max(length(causeA), length(causeB))
    x = 1:len

    figure(figsize=(7,2.8))
    if !isempty(causeA); plot(1:length(causeA), causeA, "-o", label=label_a); end
    if !isempty(causeB); plot(1:length(causeB), causeB, "-s", label=label_b); end
    yticks([0,1,2], ["other","feas","armijo"])
    xlabel("iteration (1..n)"); ylabel("stp_cause")
    title("Step cause per iteration")
    legend(); tight_layout()
    savefig(replace(out, ".png"=>"_cause.png"), dpi=180); close()
    println("Saved: ", replace(out, ".png"=>"_cause.png"))
end

# Single case visualization (if only one file is provided)
function plot_single_case(file::AbstractString; out::AbstractString="inj_single.png")
    D = load_final(file)
    print_cause_stats!(basename(dirname(file)), D)

    it, inj = get_inj_curve(D)
    figure(figsize=(6,4))
    plot(it, inj, "-o")
    xlabel("iteration"); ylabel("injection rate")
    title("Injection rate vs iteration")
    tight_layout(); savefig(out, dpi=180); close()
    println("Saved: $(out)")

    cause = get(D, "stp_cause", Int[])
    if !isempty(cause)
        figure(figsize=(7,2.8))
        plot(1:length(cause), cause, "-o")
        yticks([0,1,2], ["other","feas","armijo"])
        xlabel("iteration (1..n)"); ylabel("stp_cause")
        title("Step cause per iteration")
        tight_layout(); savefig(replace(out, ".png"=>"_cause.png"), dpi=180); close()
        println("Saved: ", replace(out, ".png"=>"_cause.png"))
    end
end
