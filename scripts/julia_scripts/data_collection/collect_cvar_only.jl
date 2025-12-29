#!/usr/bin/env julia
# Simplified script to collect only CVaR cases data
# This script reads data from CVaR directories and generates a CSV file

using Pkg
Pkg.activate(".")

using DrWatson
@quickactivate "optim_injr_DT"

using JLD2
using DataFrames
using CSV
using Statistics
using Dates

# ===================== Parameters =====================
const ROOT      = "/storage/home/hcoda1/6/hli853/p-fherrmann9-0/optim_injr_DT/data/DT_control/exp_name=step1"
const SAMPLES   = 1:64
const INIT_RATE = 1e-4

# ===================== Utility Functions =====================
function normalize_case_tag(risk_dir_name::String)
    if occursin("CVaR", risk_dir_name)
        ma = match(r"alpha\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)
        mg = match(r"gamma\s*=\s*([0-9]*\.?[0-9]+)", risk_dir_name)
        a = ma === nothing ? "?" : ma.captures[1]
        g = mg === nothing ? "?" : mg.captures[1]
        return "CVaR_g=$(g)_a=$(a)"
    end
    return risk_dir_name
end

@inline function _get(data, k::AbstractString)
    if haskey(data, k)
        return data[k]
    elseif haskey(data, Symbol(k))
        return data[Symbol(k)]
    else
        return nothing
    end
end

function _first_column(v)
    if ndims(v) == 1
        return collect(v)
    elseif ndims(v) == 2
        return vec(view(v, :, 1))
    else
        error("inj_rate_arr has unexpected dimension: $(ndims(v))")
    end
end

function last_nonzero_inj_rate(data; init_rate::Float64=INIT_RATE)
    raw = _get(data, "inj_rate_arr")
    raw === nothing && return init_rate
    col1 = _first_column(raw)
    clean = filter(x -> !(ismissing(x) || !isfinite(x)), col1)
    idx = findlast(!iszero, clean)
    return idx === nothing ? init_rate : clean[idx]
end

# ===================== Main Process =====================
println("Collecting CVaR cases data from: ", ROOT)

# Get all CVaR directories
all_dirs = filter(d -> isdir(joinpath(ROOT, d)) && occursin("CVaR", d), readdir(ROOT))
sort!(all_dirs)

println("Found $(length(all_dirs)) CVaR directories")

rows = NamedTuple[]

for risk_name in all_dirs
    case_tag = normalize_case_tag(risk_name)
    risk_dir = joinpath(ROOT, risk_name)
    
    println("Processing: $risk_name -> $case_tag")

    for s in SAMPLES
        sdir = joinpath(risk_dir, "sample=$(s)")
        final_path = joinpath(sdir, "final.jld2")

        if isfile(final_path)
            status = "ok_final"
            note = ""
            last_inj = NaN
            try
                data = load(final_path)
                last_inj = last_nonzero_inj_rate(data; init_rate=INIT_RATE)
            catch err
                status = "load_error"
                note = sprint(showerror, err)
            end
            push!(rows, (
                case_tag = case_tag,
                risk_dir = risk_name,
                sample   = s,
                status   = status,
                last_inj_rate = last_inj,
                file_used = final_path,
                note = note
            ))
        else
            push!(rows, (
                case_tag = case_tag,
                risk_dir = risk_name,
                sample   = s,
                status   = "missing",
                last_inj_rate = NaN,
                file_used = "",
                note = "no final.jld2"
            ))
        end
    end
end

df = DataFrame(rows)
println("Total rows collected: ", nrow(df))

# Count CVaR cases
df_ok = df[df.status .== "ok_final", :]
df_ok.case_tag = String.(df_ok.case_tag)
cases_cvar = unique(filter(x -> startswith(x, "CVaR"), unique(df_ok.case_tag)))
println("CVaR cases found: ", length(cases_cvar))
println("Cases: ", sort(cases_cvar))

# Save CSV
ts = Dates.format(now(), "yyyymmdd_HHMMSS")
csv_detail = joinpath(ROOT, "inj_rate_detail_$ts.csv")
CSV.write(csv_detail, df)

println("\nSaved CSV: ", csv_detail)
println("Summary:")
println("  OK (final)        : ", sum(df.status .== "ok_final"))
println("  Missing (no final): ", sum(df.status .== "missing"))
println("  Load errors       : ", sum(df.status .== "load_error"))

