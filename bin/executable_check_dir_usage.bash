#!/bin/bash

DIR="$1"
LIMIT=$((10*1024*1024*1024))

USAGE=$(du -sb "$DIR" | awk '{print $1}')

if (( USAGE < 1024*1024*1024 )); then
    USAGE_MB=$((USAGE / 1024 / 1024))
    OUT="${USAGE_MB}MB"
else
    USAGE_GB=$(awk "BEGIN {printf \"%.2f\", $USAGE/1024/1024/1024}")
    OUT="${USAGE_GB}GB"
fi

if (( USAGE > LIMIT )); then
    echo "⚠ $OUT"
else
    echo "$OUT"
fi
