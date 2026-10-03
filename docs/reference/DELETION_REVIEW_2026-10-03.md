# Approved legacy cleanup: 2026-10-03

The user approved groups G and U after reviewing this list. All 102 listed files
were deleted after verifying their recorded hashes; see the
[execution receipt](deletion_receipt_20261003.json). `CLAUDE.md` was separately
authorized for deletion after consolidating its rules in `AGENTS.md`.

The [file inventory](deletion_review_20261003.csv) records every candidate,
tracking status, size, and SHA-256 before the English-language edits. Approval
is for these paths, not a wildcard over other experiments or future files.

## G: deprecated gamma-table comparison workflow — 90 files

This group retired the entire old threshold-sweep comparison entry point,
including its optional non-table modes. The approval explicitly covered this
broader scope, not only deletion of a lookup file.

- Two implementations: `src/threshold_sensitivity.jl` and
  `src/archive/threshold_sensitivity_compact.jl`.
- Three shell entry points: `submit_gamma_table_generation.sh`,
  `submit_threshold_sensitivity.sh`, and `run_plot_threshold_sensitivity.sh`.
- Three utilities: `check_gamma_table.jl`, `view_gamma_table.jl`, and
  `check_progress.jl` (the last checks only this threshold workflow).
- Three legacy renderers: `plot_pof_vs_cvar.jl`,
  `plot_pof_cvar_comparison_advanced.jl`, and `plot_threshold_sensitivity.jl`.
- One 11,337-byte lookup table in `scripts/gamma_tables/`.
- All 78 existing files under
  `plots/DT_control/exp_name=step1/threshold_sensitivity/`: 73 PNGs and five
  reading notes, totaling 4,302,497 bytes.

The table generator and threshold submission wrapper call the two old
implementations. The plotters and progress checker read this workflow's
summary/checkpoint paths. No call from the current optimizer or selected paper
figure producers was found. The corresponding `data/` threshold-sensitivity
directory is absent locally. This is static repository evidence; it cannot
exclude someone invoking a legacy CLI manually outside this repository.

Active navigation entries were removed and retained historical method notes
now state that the workflow is retired. The explanation of why the comparison
was deprecated remains. Current PoF/CVaR optimization and ordinary CVaR
`gamma` settings are outside this group. In particular, `check_gamma0_data.jl`,
`check_gamma_matching.jl`, and `debug_gamma_data.jl` inspect ordinary CVaR case
outputs and are not gamma-table helpers.

## U: unreferenced archived variants and completed migrations — 12 files

Eight removed files in `scripts/julia_scripts/archive/` had no current runtime callers:
`optim_inject_cruyff_forward1.jl`, `optim_inject_forward1.jl`,
`optim_inject_log_barrier.jl`, `optim_inject_new_stop.jl`, `optim_inject_old.jl`,
`plot_fake.jl`, `plot_fake_old.jl`, and `test.jl`. The removed plotting examples
used synthetic data; they were not current paper figure producers.

Four completed one-time maintenance programs were also removed:
`patch_plotting_paths.py`, `patch_shell_paths.py`,
`reorganize_plotting_layout.py`, and `reorganize_shell_layout.py`. The patch
programs now map paths to identical paths; the directory migrations have
already been applied. Only these migration programs mention `plot_fake.jl`.
No runtime callers were found for any of the four migration programs.

The check covered tracked Julia, Python, and shell sources in `src/`, `scripts/`,
and `test/`, plus current figure producers and navigation. Missing callers do
not prove that an archived experiment is scientifically unimportant, so this
group was deleted only after approval. `dummy_src_file.jl` and `optim_inject_cruyff.jl`
remain because live callers still use them.

## Retained dependencies and figure documentation

Do not delete the historical posterior handoff caches, v6 statistical style
references, or relative-margin preview v2. Current renderers read their arrays,
source snapshots, or checksums. Monitoring steps, prior modes, and sensitivity
factors are separate experiments, not interchangeable versions.

`plots/paper_figures/` contains both reading notes and machine-readable export
records. `manifest.json`, `validation.json`, `input_checksums.json`, and
`delivery_checksums.json` describe how figures were produced. The latter also
hashes handoff reading notes, so moving or translating a note must be recorded
as a documentation revision rather than silently changing a signed delivery.
Immutable source snapshots and local historical bundles are not translated in
place. Nine tracked reading notes are centralized under `docs/`, with relative
links preserving their old paths; see [the location record](figure_document_locations.json).
The two translated intake notes have explicit before/after hashes in
[the English revision record](english_handoff_revision_20261003.json).
All other delivery-checksum entries remain unchanged. Current selections remain
in `plots/latest/`.

Publication cleanup must retain the transformations used in selected figures:
the posterior relative-margin sensitivity uses a 1.13 pressure-increment factor,
and the selected forward comparison includes the documented CVaR 1.22 scenario.
Removing files in a future commit will not erase prior GitHub history.
