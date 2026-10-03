# Step-2 progress checks and log locations

Run the retained progress helper from the repository root:

```bash
bash scripts/shell/check/check_step2_progress.sh
```

It reports queued/running step-2 jobs, completed `final.jld2` counts, and log
locations. Other read-only checks include:

```bash
squeue -u "$USER"
sacct -u "$USER" --format=JobID,JobName%36,State,Elapsed,ExitCode
```

Completed results live at
`data/DT_control/exp_name=step2/<case_tag>/sample=s*/final.jld2`. Case names
identify the risk configuration and prior mode, including pointwise median or
paired posterior samples. Count each case separately and distinguish active
jobs from no-final candidates.

The runtime driver specifies `logs/out_%x_%A_%a.txt` and
`logs/err_%x_%A_%a.txt`. Slurm resolves these relative to the submission
working directory. Submit from the repository root through the appropriate
wrapper; the low-level driver requires case arguments supplied by that wrapper.
Create `logs/` before submission.

The historical `../logs/` mistake was corrected on 2026-05-31, when 646 step-2
files were reported moved into the repository. Organized logs may be under
`logs/optimization/step2/`; see `logs/README.md`. The maintenance helper
`organize_logs.py` moves files and is not a read-only progress check.

Iteration artifacts use
`$SCRATCH/optim_injr_DT/DT_control/exp_name=step2/<case_tag>/sample=s*/`.
When `SCRATCH` is absent, the implementation falls back to a scratch location
under the user's home directory. Final results remain under `data/`.
