#!/usr/bin/env bash
set -euo pipefail

# Move all j=*.jld2 iteration files from data folder to scratch folder
# Preserves the original directory structure

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DATA_DIR="${ROOT_DIR}/data/DT_control"

# Determine scratch root
if [ -n "${SCRATCH:-}" ]; then
    SCRATCH_ROOT="${SCRATCH}"
elif [ -d "/scratch/${USER}" ]; then
    SCRATCH_ROOT="/scratch/${USER}"
elif [ -d "${HOME}/scratch" ]; then
    SCRATCH_ROOT="${HOME}/scratch"
else
    echo "ERROR: Cannot find scratch directory. Please set SCRATCH environment variable."
    exit 1
fi

SCRATCH_BASE="${SCRATCH_ROOT}/optim_injr_DT/DT_control"

echo "=========================================="
echo "Moving iteration files to scratch"
echo "=========================================="
echo "Source: ${DATA_DIR}"
echo "Target: ${SCRATCH_BASE}"
echo ""

# Find all j=*.jld2 files
FILES=$(find "${DATA_DIR}" -name "j=*.jld2" -type f 2>/dev/null)
TOTAL=$(echo "${FILES}" | grep -c . || echo "0")

if [ "${TOTAL}" -eq 0 ]; then
    echo "No j=*.jld2 files found to move."
    exit 0
fi

echo "Found ${TOTAL} iteration files to move"
echo ""

MOVED=0
FAILED=0

# Process each file
while IFS= read -r file; do
    [ -z "${file}" ] && continue
    
    # Get relative path from data/DT_control
    rel_path="${file#${DATA_DIR}/}"
    
    # Construct target path
    target_file="${SCRATCH_BASE}/${rel_path}"
    target_dir=$(dirname "${target_file}")
    
    # Create target directory
    mkdir -p "${target_dir}"
    
    # Move file
    if mv "${file}" "${target_file}" 2>/dev/null; then
        ((MOVED++)) || true
        if [ $((MOVED % 100)) -eq 0 ]; then
            echo "  Moved ${MOVED}/${TOTAL} files..."
        fi
    else
        echo "  ERROR: Failed to move ${file}" >&2
        ((FAILED++)) || true
    fi
done <<< "${FILES}"

echo ""
echo "=========================================="
echo "Move complete!"
echo "  Moved: ${MOVED} files"
echo "  Failed: ${FAILED} files"
echo "  Total: ${TOTAL} files"
echo "=========================================="

