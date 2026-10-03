# Scripts and archive review — 2026-10-03

This follow-up review explains the remaining historical material after the
[approved G/U deletion](DELETION_REVIEW_2026-10-03.md). The user requested a review
before deciding on further deletion. **No archive files were removed by this
review.** Sizes below count file bytes, not filesystem allocation, and describe
the local workspace on the review date.

## Scope and script improvements

The tracked `scripts/` tree contains 227 Julia, Python, and shell files:
78 Julia (19 collection, 31 plotting, 5 analysis, 21 utilities, 2 archive),
59 Python (42 plotting, 12 analysis, 5 maintenance), and 90 shell helpers
(62 submit, 9 run, 13 check, 4 retry, 2 maintenance).
No byte-identical duplicates were found among these tracked scripts. Similar
code is not necessarily interchangeable across experiments.

The follow-up changes preserve paths, CLI arguments, numerical formulas, and
selected paper assets:

- Correct the tutorial and collected-data diagnostic's relocated Julia include
  paths. Guard the legacy panel renderer's executable section so including its
  collectors does not read aggregate CSVs or generate figures. Avoid redefining
  its `ROOT` constant in the diagnostic; `DT_CONTROL_ROOT` remains supported.
- Correct the CVaR progress check's sample filter: the old regex included
  samples 60–64 and missed 109 and 119. Query full job names and allocation-only
  accounting once per service. Distinguish submission attempts from successful
  submissions, and unavailable Slurm queries from an empty queue.
- Make the PoF status helper scan all 832 configured tasks. Previously,
  `set -e` combined with post-increment counters or a missing-task return code
  could terminate the script on its first task. Match complete job names and
  reuse one queue/accounting snapshot instead of querying per sample. Preserve
  the distinction between a final file and a historical submission record.
- Make the step-1 and log organizers skip existing destinations, including
  dangling symlinks, instead of replacing artifacts. These organizers were
  exercised only in temporary test directories, not on research outputs.
- Remove stale documentation references to deleted gamma-table checks and
  one-time migration scripts.

## Remaining archive code

| File | Purpose and retained callers | Recommendation |
|---|---|---|
| `src/archive/optim_inject_7cases_fix.jl` (49,460 bytes) | Historical solver recovery variant, including line-search fallback and final-save checks. Called by `scripts/shell/run/optim_inject_pace_7cases_fix.sh` and `scripts/shell/submit/submit_missing_pof_samples_fix.sh`; the 7-missing-CVaR retry helper uses the runtime driver. | Keep while historical recovery is supported. Retire the full caller chain together only after approval. |
| `scripts/julia_scripts/archive/optim_inject_cruyff.jl` (24,182 bytes) | Old Cruyff-cluster driver using BHP and reservoir-pressure barrier terms. Called by `optim_inject_cruyff.sh` and `optim_inject_cruyff_cpu.sh` under `scripts/shell/run/`. It is not numerically equivalent to the current risk-constrained driver. | Candidate to retire with both shell callers if the Cruyff workflow is no longer needed. |
| `scripts/julia_scripts/archive/dummy_src_file.jl` (190 bytes) | DrWatson tutorial addition function, loaded by `scripts/julia_scripts/utilities/intro.jl`. No research computation. | Low-risk candidate to retire with `intro.jl`; negligible storage benefit. |

These are all three `.jl` files remaining in the two code archive directories.
They are tracked source files; root-level `archive/` is mostly local generated
material. Static references cannot establish whether an external/manual workflow
still uses a script.

## Local result archives

| Path | Contents | Size | Review recommendation |
|---|---|---:|---|
| `archive/figure_previews/` | 19 layout-preview directories (one empty): 42 PNG, 5 SVG, 19 JSON, 9 Python and 3 shell source snapshots; 78 files total. Permeability-ensemble typography, posterior/Appendix E layouts, and statistical readability iterations. No JLD2 files. | 26.78 MiB | Best first deletion candidate if layout-iteration history is no longer useful. None of the 21 selected PNG paths is inside this archive. Keep the existing relocation/provenance records. |
| `archive/logs/2025-11-24_backup_logs/` | 3,008 text logs, 5 `.out`, 5 `.err`; 3,018 files total from historical Slurm runs. | 644.38 MiB | Candidate if historical failure, timing, and submission evidence is no longer needed. Not established to be byte-for-byte duplicates elsewhere. |
| `archive/2026-04-07_step3_bad_sample_specific_injstart/` | An invalid step-3 campaign using sample-specific `inj_start` instead of one shared start per risk case. Contains 112 `final.jld2`, 1,853 PNGs, 768 text logs, and a README; 2,734 files total. | 520.89 MiB | Preserve the README and 112 final files for audit. Consider the plots and logs separately after deciding whether debugging evidence is still needed. These are not accepted current results. |

The three result groups occupy **1,249,951,515 bytes (about 1.16 GiB)** in total.
Their generated files are local and untracked; tracked root-archive content is
limited to explanatory READMEs. Local archive deletion would save disk space,
not remove these generated files from GitHub or shrink Git history.

The invalid step-3 archive breaks down as follows:

| Subdirectory | Files | Bytes | Size |
|---|---:|---:|---:|
| `data/` | 112 | 2,829,568 | 2.70 MiB |
| `plots/` | 1,853 | 201,086,477 | 191.77 MiB |
| `logs/` | 768 | 342,272,567 | 326.42 MiB |
| Root README | 1 | 796 | less than 1 KiB |

No literal root-archive paths were found in live `scripts/`, `src/`, or `test/`
callers. However, the 112 invalid-run final files are explicitly enumerated in
`docs/analysis/p1_perm_movie_audit_20260913/historical_jld2_paths.txt`. Removing
them would invalidate the local evidence inventory for that audit. Their small
size makes retaining them preferable to deleting the entire run archive.

## Further code consolidation

The step-3 and step-4 paired-posterior Python statistical plotters share much of
their rendering/bootstrapping code. Their case-level start rates, missing/active
sample records, paths, and labels differ. A future shared implementation should
first compare reconstructed 6/12 scalars, sample inclusion, bootstrap bands, and
selected q-star values on fixed small fixtures. This review does not merge them.

The legacy step-1 KDE renderers use historical scalar transformations and plotting
conventions. They should not become the default current ECDF path merely because
their imports now work. Use [the current script index](SCRIPTS_INDEX.md) and
[reproduction guide](../REPRODUCIBILITY.md) for paper work.

## Verification boundaries

Repository checks cover Python/Bash syntax, navigation, selected-asset records,
and compatibility links. Unit tests exercise submission wrappers, status
reporting, and collision preservation using temporary files and Slurm stubs.
Julia parsing and an AST comparison verify that the legacy renderer's numerical
body is unchanged apart from its direct-execution guard. Selected PNG hashes
are checked against the existing registry.

These checks do not reproduce simulations, validate numerical methods, or execute
the full Julia plotting environment. No jobs were submitted and no figures were
regenerated for this review.
