#!/usr/bin/env bash
set -euo pipefail

# ========= Configuration =========
SRC_DIR="/storage/scratch1/6/hli853/old"   # Directory to archive
ARCHIVE_DIR="/storage/coda1/p-fherrmann9/0/hli853/archives"  # Directory to store archives
mkdir -p "${ARCHIVE_DIR}"

# Generate archive name with timestamp
DATE_TAG=$(date +%Y%m%d_%H%M%S)
BASENAME=$(basename "${SRC_DIR}")
ARCHIVE_FILE="${ARCHIVE_DIR}/${BASENAME}_${DATE_TAG}.tar.gz"

# ========= Package =========
echo "[INFO] Packaging ${SRC_DIR} → ${ARCHIVE_FILE}"
tar -czf "${ARCHIVE_FILE}" -C "$(dirname "${SRC_DIR}")" "${BASENAME}"

echo "[INFO] Archive completed: ${ARCHIVE_FILE}"
ls -lh "${ARCHIVE_FILE}"

# ========= Optional: Clean up source directory =========
read -p "Delete source directory ${SRC_DIR}? [y/N]: " confirm
if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
    echo "[INFO] Deleting source directory..."
    rm -rf "${SRC_DIR}"
    echo "[INFO] Deleted ${SRC_DIR}"
else
    echo "[INFO] Keeping source directory ${SRC_DIR}"
fi
