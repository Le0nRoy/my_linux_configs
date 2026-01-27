#!/bin/bash
# Check directory disk usage and file count
# Highlights directories exceeding configured thresholds
#
# Usage: check_dir_usage.bash <directory>
#
# Output format:
#   Normal:  "dirname/: 150MB per 10 files"
#   Warning: "⚠ dirname/: 2.5GB per 25 files" (exceeds limits)
#
# Thresholds:
#   LIMIT_SIZE:  1 GB
#   LIMIT_FILES: 20 files

DIR="$1"
DIR_NAME=$(basename "${DIR}")

LIMIT_SIZE=$((1*1024*1024*1024))  # 1 GB
LIMIT_FILES=20

USAGE=$(du -sb "${DIR}" | awk '{print $1}')
COUNT=$(find "${DIR}" -type f ! -path "*/.*" | wc -l)

# форматированный размер
if (( ${USAGE} < 1024*1024*1024 )); then
    USAGE_HR=$(( ${USAGE} / 1024 / 1024 ))"MB"
else
    USAGE_HR=$(awk "BEGIN {printf \"%.2fGB\", ${USAGE}/1024/1024/1024}")
fi

# проверка лимитов
if (( ${USAGE} > ${LIMIT_SIZE} || ${COUNT} > ${LIMIT_FILES} )); then
    echo "⚠ ${DIR_NAME}/: ${USAGE_HR} per ${COUNT} files"
else
    echo "${DIR_NAME}/: ${USAGE_HR} per ${COUNT} files"
fi

