# optim_injr_DT

<div align="center">

**Optimization-based Injection Rate Control for Geological Carbon Storage**

[![Julia](https://img.shields.io/badge/Julia-1.11-blue.svg)](https://julialang.org/)
[![Python](https://img.shields.io/badge/Python-3.12-blue.svg)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/haoyunl2/optim_injr_DT/workflows/CI/badge.svg)](https://github.com/haoyunl2/optim_injr_DT/actions)

</div>

---

## 📋 Overview

This project implements a **backtracking line search gradient descent optimization solver** for geological carbon storage. The solver maximizes injected CO₂ integral while incorporating risk penalties through **Probability of Failure (POF)** and **Conditional Value at Risk (CVaR)** metrics.

### Key Features

- 🎯 **Risk-aware optimization** with POF and CVaR constraints
- 🔄 **Soft and hard constraint support** for flexible risk management
- 📊 **Comprehensive visualization** tools for results analysis
- 🧪 **Extensive test suite** for reliability
- 🚀 **HPC-ready** with SLURM job submission scripts

---

## 🚀 Quick Start

### Prerequisites

- **Julia 1.11+** ([Download](https://julialang.org/downloads/))
- **Python 3.12+** (for PyCall/PyPlot dependencies)
- **DrWatson** package (for project management)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/haoyunl2/optim_injr_DT.git
   cd optim_injr_DT
   ```

2. **Set up Julia environment:**
   ```julia
   julia> using Pkg
   julia> Pkg.add("DrWatson")  # Install globally for quickactivate
   julia> Pkg.activate(".")
   julia> Pkg.instantiate()    # Install all dependencies
   ```

3. **Verify installation:**
   ```julia
   julia --project=. test/runtests.jl
   ```

> **Note:** Raw data files are typically not included in git history and may need to be downloaded separately.

---

## 📁 Project Structure

```
optim_injr_DT/
├── src/                    # Core optimization modules
│   ├── optim_inject.jl    # Main optimization solver
│   ├── optim_inject_vecporo.jl
│   └── threshold_sensitivity.jl
│
├── scripts/               # Analysis and utility scripts
│   ├── shell/            # SLURM helpers (submit/, run/, check/, retry/, maintenance/)
│   └── julia_scripts/    # Julia scripts (organized by function)
│       ├── plotting/     # Plotting scripts
│       ├── data_collection/ # Data collection
│       ├── analysis/     # Analysis scripts
│       └── utilities/    # Utility scripts
│
├── archive/               # Superseded runs, logs, and code (reference only)
├── docs/                  # Documentation files
├── data/                  # Experiment data and results
├── plots/                 # Generated visualizations
└── test/                  # Test suite
```

For detailed structure and script entry points, see [docs/reference/DIRECTORY_STRUCTURE.md](docs/reference/DIRECTORY_STRUCTURE.md) and [docs/reference/SCRIPTS_INDEX.md](docs/reference/SCRIPTS_INDEX.md).

---

## 💻 Usage

### Running Optimization

Most scripts use DrWatson's `@quickactivate` for automatic project activation:

```julia
using DrWatson
@quickactivate "optim_injr_DT"
```

### Example: Run Optimization

```bash
julia --project=. src/optim_inject.jl --idx_num 1 --use_pof --lambda_pof 8.5e8
```

### Running Tests

```bash
julia --project=. test/runtests.jl
```

Or from Julia REPL:
```julia
include("test/runtests.jl")
```

See [test/README.md](test/README.md) for more details.

---

## 📚 Documentation

- **[Documentation Index](docs/README.md)** - Full docs map by topic
- **[Directory Structure](docs/reference/DIRECTORY_STRUCTURE.md)** - Detailed project organization
- **[Scripts Index](docs/reference/SCRIPTS_INDEX.md)** - Script entry points by purpose
- **[Optimization Choice Guide](docs/optimization/OPTIMIZATION_CHOICE_GUIDE.md)** - Algorithm selection
- **[Submit Guide](docs/workflow/SUBMIT_GUIDE.md)** - Job submission guide
- **[Script Explanation](docs/reference/SCRIPT_EXPLANATION.md)** - Detailed explanation of a specific SLURM script pattern
- **[Quick Run Guide](docs/workflow/QUICK_RUN_WITH_RISK.md)** - Quick start with risk parameters
- **[Machine-local dirs](docs/reference/MACHINE_LOCAL.md)** - `.vscode`, `.mplconfig`, `.julia_depot_*`
- **[Bootstrap CDF Methodology](docs/statistics/BOOTSTRAP_CDF_METHODOLOGY.md)** - Bootstrap/CDF plotting notes
- **[Injection Rate Arrays](docs/injection_rate_arrays.md)** - Injection ramp definitions used in plotting/export docs

---

## 🔧 Key Modules

### `optim_inject.jl`
Main optimization module supporting:
- POF/CVaR soft penalties and hard constraints
- Zero-baseline penalties
- Configurable kappa for softplus smoothing
- Comprehensive logging and visualization

### `threshold_sensitivity.jl`
Threshold sensitivity analysis for risk parameter calibration.

### `optim_inject_vecporo.jl`
Vector porosity optimization variant.

---

## 🧪 Testing

The project includes comprehensive tests covering:
- ✅ Utility functions (softplus, array operations)
- ✅ Risk metrics (POF, CVaR computations)
- ✅ Data I/O operations
- ✅ Optimization functions

Run all tests:
```bash
julia --project=. test/runtests.jl
```

---

## 🖥️ HPC Usage

For cluster environments (e.g., PACE), use the scripts in `scripts/shell/`:

```bash
# Submit batch jobs
./scripts/shell/submit/submit_all.sh

# Run the bootstrap CDF workflow
bash scripts/shell/run/run_bootstrap_cdf.sh
```

---

## 📦 Dependencies

### Core Julia Packages
- `JutulDarcyRules` - Reservoir simulation
- `SlimOptim` - Optimization algorithms
- `DrWatson` - Project management
- `JLD2` - Data storage
- `PyCall` / `PyPlot` - Python integration for plotting

See [Project.toml](Project.toml) for complete dependency list.

---

## 👤 Author

**Haoyun Li**

---

## 📄 License

This project is licensed under the MIT License.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📝 Citation

If you use this code in your research, please cite:

```bibtex
@software{optim_injr_DT,
  author = {Haoyun Li},
  title = {optim_injr_DT: Optimization-based Injection Rate Control for Geological Carbon Storage},
  year = {2024},
  url = {https://github.com/haoyunl2/optim_injr_DT}
}
```

---

<div align="center">

**Made with ❤️ using Julia**

</div>
