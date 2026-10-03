# Historical analysis of seven missing samples

This note records a past seven-case recovery investigation. Counts and line
numbers describe that investigation, not the current campaign. The diagnostic
scalar here is `(last_nonzero + 0.0001) / 2`; it is not the current `6/12`
schedule element used in the paper statistics.

## Recorded values

| Case | Sample | Last nonzero (m³/s) | Historical averaged rate (m³/s) |
|---|---:|---:|---:|
| gamma=0.01, alpha=0.02 | 64 | 0.762500 | 0.381300 |
| gamma=0.01, alpha=0.05 | 17 | 0.145750 | 0.072925 |
| gamma=0.02, alpha=0.01 | 64 | 0.762500 | 0.381300 |
| gamma=0.05, alpha=0.02 | 42 | 0.336500 | 0.168300 |
| gamma=0.05, alpha=0.05 | 1 | 0.299000 | 0.149550 |
| gamma=0.05, alpha=0.05 | 21 | 0.249000 | 0.124550 |
| gamma=0.05, alpha=0.05 | 64 | 1.301562 | 0.650831 |

## Line-search failure investigation

The reported error was `UndefVarError: stp not defined`. The old loop initialized
`stp = ex_step_size`, called `ls(...)`, and tried `theta(0.001)` after an exception.
That fallback evaluation could itself throw an uncaught exception. This was a
suspected failure path; the note alone does not establish the cause of every
missing result.

The archived `optim_inject_7cases_fix.jl` added an explicit validity flag and a
nested handler:

```julia
stp = ex_step_size
obj_valid = false
try
    stp, obj = ls(θ, ex_step_size, obj, dot(grad, p))
    obj_valid = isfinite(obj) && obj != Inf
catch e
    println("Warning: line search failed at iteration $j: ", e)
    stp = 0.001
    try
        obj = θ(stp)
        obj_valid = isfinite(obj) && obj != Inf
    catch e2
        println("Small step evaluation also failed: ", e2)
    end
end
if !obj_valid
    stp = ex_step_size
    break
end
ex_step_size = stp
```

## Missing final files

The investigation considered missing output directories, filesystem errors,
and interrupted optimization. The recovery variant checked `isdir(out_root)`,
created the directory if needed, wrapped `@tagsave` in `try/catch`, and verified
`isfile(final_path)` after saving. It logged the path and exception on failure.
The earlier note's claim that `safe=true` suppresses all save exceptions was
not established by this investigation; do not rely on it.

## Group statistics

`scripts/julia_scripts/data_collection/collect_all_injection_rates.jl` groups
completed samples by `case_tag` (the gamma/alpha combination):

```julia
function group_stats(df::DataFrame)
    g = groupby(df, :case_tag)
    combine(g,
        nrow => :count,
        :last_inj_rate => mean => :mean,
        :last_inj_rate => (v -> (length(v) > 1 ? std(v) : 0.0)) => :std,
    )
end
```

The recorded example had 61 completed `CVaR_g=0.05_a=0.05` samples, with mean
0.465198 and standard deviation 0.263584. The illustrative mean ± 2 SD range
was [-0.061971, 0.992366]; it is not an automatic exclusion rule. The seven
samples were absent from those statistics because they had no `final.jld2` at
the time. Recollecting after recovery changes the sample set and statistics.
