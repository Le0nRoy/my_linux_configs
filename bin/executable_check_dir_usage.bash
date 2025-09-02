#!/bin/bash

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

