#!/usr/bin/env julia
# Read-only report exporter; retain the repository activation pattern.
using Pkg
Pkg.activate(".")
using DrWatson
@quickactivate "optim_injr_DT"

# JLD2 0.4.55 misreconstructs a nested tolerance dictionary in these reports.
# Read named HDF5 fields instead; original data/type declarations stay untouched.
# Pressure and checkpoint arrays load independently through JLD2.
length(ARGS)==2 || error("Usage: summarize_zero_pressure_solver.jl AUDIT_ROOT NEW_CSV")
script=scriptsdir("python_tools","analysis","summarize_zero_pressure_solver_hdf5.py")
run(`python3 $script $(ARGS[1]) $(ARGS[2])`)
