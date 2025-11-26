# Shared utility functions for optim_injr_DT project

"""
    setup_pycall()

Configure PyCall to use the correct Python interpreter based on the environment.
Automatically detects PACE cluster environment and sets up Python path accordingly.
"""
function setup_pycall()
    if Base.get(ENV, "LMOD_SITE_NAME", "") == "PACE"
        println("PACE environment detected. Setting PyCall Python path...")
        ENV["PYTHON"] = "/usr/local/pace-apps/manual/packages/anaconda3/2023.03/bin/python"
        Pkg.build("PyCall")
    else
        println("Non-PACE environment detected. Skipping PyCall config.")
    end
end

export setup_pycall


