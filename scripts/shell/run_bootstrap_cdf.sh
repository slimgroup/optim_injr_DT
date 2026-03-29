#!/bin/bash
# Run bootstrap CDF plotting on a compute node (or interactive salloc), not the login node.
#
# Usage (from repo root):
#   bash scripts/shell/run_bootstrap_cdf.sh
#   BOOTSTRAP_QUICK=1 bash scripts/shell/run_bootstrap_cdf.sh   # Part 1 + Part 1b only (no 4×3 grids)
#
# Uses the project environment. Julia depot: only $HOME/.julia (do not set a repo-local depot).
# Override only if you know what you are doing: export JULIA_DEPOT_PATH=...

set -euo pipefail

if [[ -n "${REPO_ROOT:-}" ]]; then
  cd "$REPO_ROOT"
elif [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  REPO_ROOT="$SLURM_SUBMIT_DIR"
  cd "$REPO_ROOT"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  cd "$REPO_ROOT"
fi

export JULIA_DEPOT_PATH="${JULIA_DEPOT_PATH:-$HOME/.julia}"
mkdir -p "$JULIA_DEPOT_PATH"

module purge 2>/dev/null || true
if module load julia/1.12.5 2>/dev/null; then
  :
elif module load julia/1.11.3 2>/dev/null; then
  :
elif module load julia/1.10.1 2>/dev/null; then
  :
elif module load julia 2>/dev/null; then
  :
else
  echo "ERROR: could not module load julia" >&2
  exit 1
fi

JLP="scripts/julia_scripts/plotting/plot_bootstrap_panels.jl"

echo "Repo: $REPO_ROOT"
echo "Julia: $(command -v julia) ($(julia --version))"
echo "JULIA_DEPOT_PATH=$JULIA_DEPOT_PATH"
date -Is

if [[ "${BOOTSTRAP_QUICK:-0}" == "1" ]]; then
  echo "=== BOOTSTRAP_QUICK=1: Part 1 (cdf_POF_eps0.01, cdf_CVaR_...) then Part 1b (cdf_POF_eps0, cdf_CVaR_g0.1_a0.01) ==="
  BOOTSTRAP_ONLY_PART1=1 julia --project=. "$JLP"
  BOOTSTRAP_ONLY_INJ6=1 julia --project=. "$JLP"
else
  echo "=== Full pipeline: Part 1 + Part 1b + 4×3 grids (longer) ==="
  julia --project=. "$JLP"
fi

echo "Done."
date -Is
