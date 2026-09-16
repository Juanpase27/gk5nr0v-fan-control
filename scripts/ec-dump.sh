#!/usr/bin/env bash
# Capture a timestamped EC dump (hexdump -C format, 256 bytes).
# Usage: sudo ./ec-dump.sh [output_file]
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: run as root" >&2
    exit 1
fi

out="${1:-ec_dump_$(date +%Y%m%d_%H%M%S).txt}"
hexdump -C /sys/kernel/debug/ec/ec0/io > "$out"
echo "saved $out"
