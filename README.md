# optim_injr_DT

This code base is using the [Julia Language](https://julialang.org/) and
[DrWatson](https://juliadynamics.github.io/DrWatson.jl/stable/)
to make a reproducible scientific project named
> optim_injr_DT

It is authored by Haoyun Li.

To (locally) reproduce this project, do the following:

0. Download this code base. Notice that raw data are typically not included in the
   git-history and may need to be downloaded independently.
1. Open a Julia console and do:
   ```
   julia> using Pkg
   julia> Pkg.add("DrWatson") # install globally, for using `quickactivate`
   julia> Pkg.activate("path/to/this/project")
   julia> Pkg.instantiate()
   ```

This will install all necessary packages for you to be able to run the scripts and
everything should work out of the box, including correctly finding local paths.

You may notice that most scripts start with the commands:
```julia
using DrWatson
@quickactivate "optim_injr_DT"
```
which auto-activate the project and enable local path handling from DrWatson.

## Project Structure

- `src/`: Core module code (optim_inject.jl, threshold_sensitivity.jl, etc.)
- `scripts/`: All script files
  - `shell/`: Shell scripts (SLURM job submission, etc.)
  - `julia_scripts/`: Julia scripts (data processing, plotting, analysis, etc.)
- `data/`: Data files (experiment data, intermediate results, etc.)
- `plots/`: Generated image files
- `test/`: Test code
  - See [test/README.md](test/README.md) for running tests

For detailed directory structure, please refer to [DIRECTORY_STRUCTURE.md](DIRECTORY_STRUCTURE.md)

## Running Tests

To run the test suite:

```julia
julia --project=. test/runtests.jl
```
