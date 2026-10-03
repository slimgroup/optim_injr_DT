# Running a selected campaign across samples 1–128

Choose the established submission wrapper for the required monitoring step,
risk case, and prior mode from [SCRIPTS_INDEX.md](../reference/SCRIPTS_INDEX.md).
Inspect its sample range and completion checks before submission. Preserve the
case-level starting rate and paired posterior-state rules in
[AGENTS.md](../../AGENTS.md).

Slurm arrays can map `SLURM_ARRAY_TASK_ID` to `--idx_num`, but adding an array to
a wrapper that already submits jobs can duplicate a campaign. Use the existing
wrapper interface rather than copying the old illustrative templates from
previous revisions of this guide. Run a supported smoke test first, then submit
the intended range in resource-appropriate batches. Completed `final.jld2`
files and active jobs must be checked before retries.

The historical planning example involved 11 cases × 128 samples = 1,408 jobs,
with a rough 15–16 hours per case and approximately 22,000 serial compute hours.
Those are old estimates, not current queue status or measured requirements.
Its `ex_step_size=0.1` statement also described an earlier variant.

Monitor storage and log growth. The old `--save_every 5` suggestion should only
be used if supported by the chosen entry point and consistent with required
checkpoints. Do not change checkpoint retention during an unrelated cleanup.
See [PACE_RUN_GUIDE.md](PACE_RUN_GUIDE.md) for environment and depot setup.
