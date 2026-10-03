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

The existing `organize_*`, `reorganize_*`, and `patch_*_paths.py` scripts may move
or rewrite files. They are historical maintenance tools, not installation
steps. Review their scope and the [cleanup record](../../docs/reference/REPOSITORY_CLEANUP.md)
before use.
