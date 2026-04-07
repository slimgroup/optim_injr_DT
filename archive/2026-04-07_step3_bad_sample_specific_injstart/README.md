This archive contains the first step-3 paired-posterior run that used the wrong `inj_start` rule.

Why it is archived:
- The run used sample-specific `inj_start` values recovered from previous-step per-sample optimization outputs.
- The correct workflow is case-level `inj_start`: every sample within the same case must share the same starting rate.
- The correct case-level values come from the previous monitoring step's selected optimal injection-rate array documented in `docs/injection_rate_arrays.md`.

Archived contents:
- `data/DT_control/exp_name=step3`: saved optimization outputs from the incorrect run
- `plots/DT_control/exp_name=step3`: saved plots/states from the incorrect run
- `logs/`: SLURM stdout/stderr logs for jobs `6308432`, `6308433`, `6311583`, `6312047`, and `6312175`
