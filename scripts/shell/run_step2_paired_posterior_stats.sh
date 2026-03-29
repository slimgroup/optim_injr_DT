#!/bin/bash

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

echo "Repo: $REPO_ROOT"
echo "Python: $(command -v python)"
date -Is

export MPLCONFIGDIR="${MPLCONFIGDIR:-/tmp/matplotlib-codex}"
mkdir -p "$MPLCONFIGDIR"

python scripts/julia_scripts/plotting/plot_step2_paired_posterior_stats.py

echo "Done."
date -Is
