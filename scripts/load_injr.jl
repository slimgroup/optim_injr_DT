using DrWatson
@quickactivate "optim_injr_DT" # <- project name
using JLD2
# using FilePathsBase  # Only needed if you're working with paths as objects
# using FileIO  # Needed for `@tagload`

# Set parameters consistent with how it was saved
sim_name = "DT_control"
exp_name = "step1" # which step to control in DT
s = 1  # sample number

# Load all variables from file into a dictionary
data = load(filepath)

# Now access variables from the dictionary
inj_rate_arr = data["inj_rate_arr"]
step_arr = data["step_arr"]
obj_arr = data["obj_arr"]
obj_1_arr = data["obj_1_arr"]
obj_2_arr = data["obj_2_arr"]
obj_arr_arr = data["obj_arr_arr"]

# Now the variables inj_rate_arr, step_arr, etc. are available in your workspace
