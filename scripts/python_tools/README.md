# python_tools/

Python utilities that maintain repository layout or organize generated artifacts.

```text
python_tools/
└── maintenance/
    ├── organize_logs.py
    ├── organize_step1_data.py
    ├── organize_dt_control_plots.py
    ├── reorganize_shell_layout.py
    ├── patch_shell_paths.py
    ├── reorganize_plotting_layout.py
    └── patch_plotting_paths.py
```

These scripts are Python maintenance tools, not SLURM entry points. Run them from
the repository root unless the script says otherwise.

Common commands:

```bash
python3 scripts/python_tools/maintenance/organize_logs.py
python3 scripts/python_tools/maintenance/organize_step1_data.py
python3 scripts/python_tools/maintenance/organize_dt_control_plots.py
```
