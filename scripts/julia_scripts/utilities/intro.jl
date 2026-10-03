using DrWatson
@quickactivate "optim_injr_DT"

# Load the retained DrWatson tutorial example.
include(joinpath(@__DIR__, "..", "archive", "dummy_src_file.jl"))

println(
"""
Currently active project is: $(projectname())

Path of active project: $(projectdir())

Have fun with your new project!

You can help us improve DrWatson by opening
issues on GitHub, submitting feature requests,
or even opening your own Pull Requests!
"""
)
