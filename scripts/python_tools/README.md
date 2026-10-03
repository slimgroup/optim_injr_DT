# Python tools

`analysis/` contains post-processing and diagnostic helpers.
`maintenance/` contains repository checks and historical artifact migrations.

Safe read-only checks, from the repository root:

```bash
python3 scripts/python_tools/maintenance/check_repository.py
python3 scripts/python_tools/maintenance/check_repository.py --paper-assets
```

The second command verifies selected local PNG checksums and requires those
assets. Neither command runs simulations or contacts Slurm.

The retained `organize_logs.py`, `organize_step1_data.py`, and
`organize_dt_control_plots.py` move local artifacts. Review their scope and the
[cleanup record](../../docs/reference/REPOSITORY_CLEANUP.md) before running them;
they are historical maintenance tools, not installation steps. The log and
step-1 organizers skip existing destinations, including dangling symlinks.

`assemble_paper_figures.py` writes figure assets and an index. Run it only for
an intended figure-selection update; it is not a read-only repository check.
