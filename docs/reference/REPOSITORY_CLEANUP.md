# Repository cleanup record

Status: the initial organization and the subsequent approved legacy cleanup are
complete. The user authorized cleanup, commit, and remote synchronization on
2026-10-03, then approved the exact legacy deletion groups. No simulation or plot
was rerun. The first phase preserved all outputs; the second deleted only the
reviewed obsolete workflow and its listed artifacts, as recorded below.

## Second-phase review and completion

- Deleted the explicitly approved G and U groups: 102 files, 4,682,535 bytes.
  G contains the retired gamma-table/threshold workflow, one table, and 78 old
  outputs; U contains eight unreferenced archived variants and four completed
  path-migration scripts. Every file matched its review hash before deletion.
  See [scope and dependencies](DELETION_REVIEW_2026-10-03.md),
  [exact paths](deletion_review_20261003.csv), and
  [execution receipt](deletion_receipt_20261003.json).
- Consolidated agent rules in `AGENTS.md`, removed the explicitly authorized
  `CLAUDE.md`, and reduced both Cursor rules to pointers to the canonical file.
- Standardized tracked natural-language documentation, comments, and terminal
  messages to English. Preserved filenames, data keys, CLI arguments, and
  executable behavior. The deletion CSV intentionally retains one original
  Chinese filename as a historical path identifier.
- Replaced contradictory old method advice with concise English explanations
  referring to the current solver description. In particular, nonzero lambda
  remains active with hard checks; zero-baseline penalties can be negative;
  the stopping heuristic does not prove 95% accuracy. Old timing forecasts are
  labeled as estimates. Diagnostic outlier messages no longer imply that a
  mean ± 2 SD flag alone justifies removing a completed sample.
- Centralized nine figure reading notes under `docs/`, deduplicating two against
  existing analysis documents. Relative links preserve all original export
  paths and byte content. See [the location map](figure_document_locations.json).
  The two translated paper-intake notes have explicit old/new hashes in
  [the language revision record](english_handoff_revision_20261003.json);
  only their entries changed in the delivery checksum files. Original ZIPs and
  source snapshots remain unchanged local historical records.
- Preserved all 21 selected PNG hashes, current numerical inputs, prior exports,
  and the documented 1.13/1.22 sensitivity interpretations. The removed
  gamma-table calibration is separate from ordinary CVaR gamma parameters.

The second-phase checks cover 24 navigation documents, 61 Python files,
90 shell scripts, nine document compatibility links, and 21 selected-asset
hashes. Four isolated submission tests pass. Julia parsing confirms that all
ten translated Julia sources retain identical executable ASTs and interpolation
expressions, with only comments and Chinese string literals changed. No Julia
package installation, simulation, heavy integration test, rendering, or real
Slurm submission was performed. An independent staged-only export passed the
repository/asset checks and the four submission tests. Its 400 readable text
files passed the English-language scan, with the original inventory filename
retained as noted above. A wider link scan found 119 references to intentionally
local data, videos, and historical outputs: all still exist locally but are not
included in the public checkout. Maintained navigation and selected assets pass
without those files. The following sections retain the first-phase record.

## Completed organization

- Replaced the overview with a paper-facing README, reproduction guide, truthful
  data-availability statement, citation metadata, and observed Python dependencies.
- Moved 22 older notes into `docs/historical/`; updated documentation links.
  Kept exporter-consumed documents and evidence directories at stable paths.
- Replaced the deprecated PACE quick-start entry with current submission examples.
- Condensed directory/script navigation and generic Git attribute/ignore templates.
  Selected posterior 1.13 PNGs and split statistical panels are explicitly allowed.
- Recorded 21 selected PNGs and their SHA-256 hashes in
  [paper_assets.json](paper_assets.json); preserved sensitivity qualifications.
- Corrected stale root/driver paths in 33 shell helpers. Case definitions,
  optimizer arguments, resource defaults, and Julia activation are unchanged.
- Added read-only repository checks, isolated submission-interface tests, and
  a separate source/layout CI job.

The working tree already contained staged, unstaged, and untracked research
changes. Those changes were retained. In particular, a pressure-trajectory PNG
had a staged deletion and an unstaged local replacement. The first phase left
the index as found; the authorized commit retains the latest working PNG, along
with the pending research scripts and analysis records.

## Completed artifact cleanup

The approved paths, destinations, file counts, and sizes are in
[cleanup_candidates.csv](cleanup_candidates.csv). The completed actions and
per-file SHA-256 hashes are in [cleanup_receipt.json](cleanup_receipt.json):

1. Archived **19 obsolete layout-preview directories** (78 files, 26.8 MiB) from `plots/paper_figures/` to `archive/figure_previews/`, preserving their names and contents. The current Julia/Python/shell source has no literal references to these directory names. This is a source-reference check, not proof that no external manuscript uses them.
2. Stopped tracking **64 historical generated files** in Git, leaving every local file at the same path. This covers step-1 label revisions v3–v5, the old posterior PNG/PDF/SVG set, and old combined step-2–4 histogram/ECDF exports. Existing staged changes are excluded. Git history remains intact.

No data/JLD2, logs, user scripts, selected paper PNGs, v6/v7 label revisions,
1.13/1.145 sensitivity bundles, forward results, or numerical source caches
were included. This cleanup performed no permanent artifact deletion.
It removes older figure versions from the active paper directory and/or the
future source tree while retaining the material needed to audit past work.

The user approved this scope in the conversation. All 78 archived files and
64 locally retained exports were checked against their recorded hashes.

`plots/latest/` now presents the 21 selected figures through relative links,
with a Markdown index and local HTML gallery. Original numerical inputs and
figure paths remain available. The current view does not duplicate image data.

The `.gitignore` policy also excludes archived log subdirectories, preserving
the earlier `logs/` behavior and preventing local job records from being staged.

## Why some old-looking files remain

- `labels_reviewed_v6_20260915` is read by `restyle_paper_pngs.py` and the
  observed-jump comparison; keep it as an input.
- `posterior_relative_margin_preview_20261002_v2` contains arrays read by the
  selected 1.13 renderer. It is not disposable preview imagery.
- `posterior_appendix_e_handoff_ecdf_only_20260909` contains the historical
  numerical snapshots used by later paper layouts.
- The 64-member forward run/reference is reused by the 128-member comparison.
- Historical Julia source variants and legacy plots still have callers.
- First through fourth monitoring-step exports are distinct stages, not older
  versions of a single dataset. All remain necessary for reproduction.
- Presentation movies, log files, and downloaded reference evidence remain
  local. The source repository should not claim these are distributed datasets.

## Document relocation map

| Previous path | Current path |
|---|---|
| `docs/analysis/BHP_FOUR_STRATEGIES_PAPER_NOTE_2026-09-07.md` | `docs/historical/analysis/BHP_FOUR_STRATEGIES_PAPER_NOTE_2026-09-07.md` |
| `docs/analysis/BHP_GROUND_TRUTH_AUDIT_2026-09-07.md` | `docs/historical/analysis/BHP_GROUND_TRUTH_AUDIT_2026-09-07.md` |
| `docs/analysis/BHP_PAPER_REPO_HANDOFF_2026-09-07.md` | `docs/historical/analysis/BHP_PAPER_REPO_HANDOFF_2026-09-07.md` |
| `docs/analysis/JOINT_PERMEABILITY_64_DAY1920_2026-09-15.md` | `docs/historical/analysis/JOINT_PERMEABILITY_64_DAY1920_2026-09-15.md` |
| `docs/analysis/JOINT_PERMEABILITY_MOVIE_2026-09-14.md` | `docs/historical/analysis/JOINT_PERMEABILITY_MOVIE_2026-09-14.md` |
| `docs/analysis/POSTERIOR_ALL_CASES_VIDEO_K1_2026-09-14.md` | `docs/historical/analysis/POSTERIOR_ALL_CASES_VIDEO_K1_2026-09-14.md` |
| `docs/analysis/POSTERIOR_COMPACT_LAYOUT_2026-09-15.md` | `docs/historical/analysis/POSTERIOR_COMPACT_LAYOUT_2026-09-15.md` |
| `docs/analysis/POSTERIOR_MARGIN_SENSITIVITY_1P145_2026-10-02.md` | `docs/historical/analysis/POSTERIOR_MARGIN_SENSITIVITY_1P145_2026-10-02.md` |
| `docs/analysis/POSTERIOR_PRESENTATION_36S_2026-09-14.md` | `docs/historical/analysis/POSTERIOR_PRESENTATION_36S_2026-09-14.md` |
| `docs/analysis/POSTERIOR_RELATIVE_MARGIN_PREVIEW_2026-10-02.md` | `docs/historical/analysis/POSTERIOR_RELATIVE_MARGIN_PREVIEW_2026-10-02.md` |
| `docs/analysis/POSTERIOR_SAMPLE_VIDEO_K1_2026-09-13.md` | `docs/historical/analysis/POSTERIOR_SAMPLE_VIDEO_K1_2026-09-13.md` |
| `docs/analysis/PRESSURE_HISTORY_PRESENTATION_2026-09-15.md` | `docs/historical/analysis/PRESSURE_HISTORY_PRESENTATION_2026-09-15.md` |
| `docs/analysis/ZERO_INJECTION_PRESSURE_AUDIT_2026-09-09.md` | `docs/historical/analysis/ZERO_INJECTION_PRESSURE_AUDIT_2026-09-09.md` |
| `docs/optimization/OPTIM_INJECT_REFACTOR_NOTES.md` | `docs/historical/optimization/OPTIM_INJECT_REFACTOR_NOTES.md` |
| `docs/reference/REPO_MAINTENANCE_AUDIT_2026-06-15.md` | `docs/historical/reference/REPO_MAINTENANCE_AUDIT_2026-06-15.md` |
| `docs/statistics/FIGURES_6_7_DECIMAL_FORMATTING_2026-09-09.md` | `docs/historical/statistics/FIGURES_6_7_DECIMAL_FORMATTING_2026-09-09.md` |
| `docs/statistics/KDE_CI_METHODOLOGY.md` | `docs/historical/statistics/KDE_CI_METHODOLOGY.md` |
| `docs/statistics/POF_ECDF_JUMP_COMPARISON_2026-09-16.md` | `docs/historical/statistics/POF_ECDF_JUMP_COMPARISON_2026-09-16.md` |
| `docs/statistics/STATISTICAL_FIGURE_LABELS_2026-09-15.md` | `docs/historical/statistics/STATISTICAL_FIGURE_LABELS_2026-09-15.md` |
| `docs/statistics/STEP1_ECDF_OBSERVED_JUMPS_2026-09-16.md` | `docs/historical/statistics/STEP1_ECDF_OBSERVED_JUMPS_2026-09-16.md` |
| `docs/workflow/PACE_RUN_GUIDE.md` | `docs/historical/workflow/PACE_RUN_GUIDE.md` |
| `docs/workflow/STEP2_LOGS_AND_PROGRESS.md` | `docs/historical/workflow/STEP2_LOGS_AND_PROGRESS.md` |

The original gamma-table `PACE_RUN_GUIDE.md` was archived; a new current guide
now occupies its previous path. Old reference evidence folders remain under
`docs/analysis/` because audit and presentation scripts may refer to them.

## Checks and remaining release information

Validation uses source syntax checks, maintained-document links, selected PNG
checksums, and real submission wrappers with a temporary `sbatch` stub. It does
not run a simulation, submit a job, or revalidate the scientific results.
All checks passed: 21 maintained navigation documents, 65 Python files,
93 shell scripts, 21 selected PNG checksums, and four submission test methods
(nine wrapper invocations, 27 stubbed submissions). A wider scan found no
broken local Markdown links in `docs/`, `scripts/`, `test/`, or `src/`.
The four existing analytical pressure-diagnostic tests also passed. Small
duplicate-value and all-equal sample checks verified the pending Python
step-2–4 ECDF changes: observed jumps, right-continuous values, deterministic
bootstrap bands, and crossings at observed samples. These are lightweight
analytical checks, not a rerun of the posterior campaigns or Julia bootstrap.
Before the authorized index changes, the original staged diff was verified
unchanged, and all 108 previously inventoried output/core-code files retained
their original checksums. Selected output hashes remain unchanged after cleanup.
An independent export of the Git staging area passed the same repository/asset
checks and all eight lightweight unit tests without local untracked files.
Every staged blob was compared with that tested export.
The Julia dependency installation and numerical test suite were not rerun for
this organizational change. Data access details, paper bibliographic metadata,
and the release commit/tag still need to be supplied for public reproduction.

## Agent-instruction review

`AGENTS.md` already covered scientific definitions, posterior pairing, case-level
starting rates, artifact protection, and PACE resource rules. The maintenance
update adds selection precedence, reversible archive records, dependency checks,
lightweight verification commands, preservation of existing work, staged-only
checkout validation, and fetch/compare/verify rules for requested synchronization.
It also avoids asking again for a commit that the user has already authorized.
Scientific rules and the restriction on unrequested destructive cleanup remain.

This keeps repository-specific instructions in the root file and points to
method documents only when relevant, following the
[official AGENTS.md guidance](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
