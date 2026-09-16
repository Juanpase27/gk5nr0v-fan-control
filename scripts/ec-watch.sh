#!/usr/bin/env bash
# Live EC monitor for TongFang GK5NR0V / EVOO EG-LP7.
# Shows the EC rows that contain temps and fan telemetry (0x30, 0x40, 0x60).
# Usage: sudo ./ec-watch.sh [interval_seconds]
set -euo pipefail

interval="${1:-2}"

if [[ $EUID -ne 0 ]]; then
    echo "error: run as root (debugfs EC access requires it)" >&2
    exit 1
fi

modprobe ec_sys write_support=1 2>/dev/null || true

if [[ ! -r /sys/kernel/debug/ec/ec0/io ]]; then
    echo "error: /sys/kernel/debug/ec/ec0/io not readable" >&2
    echo "hint: sudo modprobe ec_sys write_support=1" >&2
    exit 1
fi

watch -n "$interval" "hexdump -C /sys/kernel/debug/ec/ec0/io | sed -n '4p;5p;7p'"
