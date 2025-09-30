#!/usr/bin/env bash
set -euo pipefail

# ========= 配置区 =========
SRC_DIR="/storage/scratch1/6/hli853/old"   # 要归档的目录
ARCHIVE_DIR="/storage/coda1/p-fherrmann9/0/hli853/archives"  # 存放归档的目录
mkdir -p "${ARCHIVE_DIR}"

# 生成带时间戳的归档名
DATE_TAG=$(date +%Y%m%d_%H%M%S)
BASENAME=$(basename "${SRC_DIR}")
ARCHIVE_FILE="${ARCHIVE_DIR}/${BASENAME}_${DATE_TAG}.tar.gz"

# ========= 打包 =========
echo "[INFO] 打包 ${SRC_DIR} → ${ARCHIVE_FILE}"
tar -czf "${ARCHIVE_FILE}" -C "$(dirname "${SRC_DIR}")" "${BASENAME}"

echo "[INFO] 归档完成: ${ARCHIVE_FILE}"
ls -lh "${ARCHIVE_FILE}"

# ========= 可选：清理原目录 =========
read -p "是否删除源目录 ${SRC_DIR}? [y/N]: " confirm
if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
    echo "[INFO] 删除源目录..."
    rm -rf "${SRC_DIR}"
    echo "[INFO] 已删除 ${SRC_DIR}"
else
    echo "[INFO] 保留源目录 ${SRC_DIR}"
fi
