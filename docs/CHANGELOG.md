# Changelog

## Repository Organization (2024-11-24) - Updated

### ✨ Latest Improvements

#### Documentation Organization
- **Created `docs/` directory** for all documentation files
  - Moved all `.md` documentation files to `docs/`
  - Created `docs/README.md` as documentation index
  - Updated all documentation links in main README

#### Script Organization
- **Created `scripts/julia_scripts/utilities/`** directory
  - Moved utility scripts (scaling, tuning, etc.) to utilities/
  - Better categorization of scripts by function

#### Root Directory Cleanup
- **Moved `run_quick_sensitivity.sh`** to `scripts/shell/`
- **Moved `check_progress.jl`** to `scripts/julia_scripts/utilities/`
- Root directory now only contains essential files (README.md, Project.toml, Manifest.toml)

---

## Repository Organization (2024-11-24)

### ✨ Improvements

#### README Enhancement
- **Redesigned README** with modern formatting
  - Added badges for Julia, Python, License, and CI status
  - Improved structure with clear sections and emojis
  - Added Quick Start guide
  - Enhanced documentation links
  - Added citation information

#### Directory Organization
- **Scripts reorganization:**
  - Created `scripts/julia_scripts/plotting/` for all plotting scripts
  - Created `scripts/julia_scripts/data_collection/` for data collection scripts
  - Created `scripts/julia_scripts/analysis/` for analysis scripts
  - Moved all scripts from root `scripts/` to appropriate subdirectories

- **Plots organization:**
  - Moved `plots_fake/`, `plots_fake_v2/`, `plots_sep/`, `plots_unified/` to `plots/archive/`
  - All plot directories now under `plots/` for better organization

#### CI Configuration
- Updated Julia version to **1.11**
- Updated Python version to **3.12** with `check-latest: true`
- Added proper Python environment setup for PyCall/PyPlot
- Improved error handling in CI workflow

#### Documentation
- Updated `DIRECTORY_STRUCTURE.md` to reflect new organization
- Enhanced project structure documentation

### 📁 Current Structure

```
optim_injr_DT/
├── src/                    # Core modules (3 files)
├── scripts/
│   ├── shell/             # Shell scripts (SLURM, etc.)
│   └── julia_scripts/     # Julia scripts (organized by function)
│       ├── plotting/      # Plotting scripts
│       ├── data_collection/ # Data collection
│       ├── analysis/      # Analysis scripts
│       └── archive/       # Old versions
├── data/                   # Experiment data
├── plots/                  # All plots (including archive)
├── test/                   # Test suite
└── docs/                   # Documentation files
```

### 🧪 Testing
- Comprehensive test suite with 60+ tests
- All tests passing
- Test documentation in `test/README.md`

---

## Previous Organization (Before 2024-11-24)

### Initial Cleanup
- Moved PNG files from root to `plots/root/`
- Moved `.jld2` data files to `data/scripts_data/`
- Moved shell scripts from `src/` to `scripts/shell/`
- Moved old/archived scripts to `archive/` directories
- Updated path references in scripts

