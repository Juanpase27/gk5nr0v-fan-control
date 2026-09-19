#!/usr/bin/env bash
# Measure how quickly the GK5NR0V firmware reverts a direct write to EC 0x3E
# (fan duty), and whether the CPU fan (tach 0x60-0x61 BE16) obeys meanwhile.
#
# Run with the nbfc service STOPPED (so the only competing writer is firmware):
#   sudo systemctl stop nbfc_service
#   sudo ./scripts/ec-write-latency.sh
#   sudo systemctl start nbfc_service
#
# Writes only 0x3E with values 31 and 78 (both already written by nbfc today).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="/sys/kernel/debug/ec/ec0/io"
OUT="$REPO_ROOT/data/tests/write_latency_$(date +%Y%m%d_%H%M%S).csv"
mkdir -p "$(dirname "$OUT")"

if [[ $EUID -ne 0 ]]; then echo "error: run as root" >&2; exit 1; fi
if systemctl is-active --quiet nbfc_service; then
    echo "error: stop nbfc_service first (it would compete for 0x3E)" >&2
    exit 1
fi

# decimal offsets: duty=62(0x3E) | cpu tach: 96,97(0x60,0x61) | gpu tach: 104,105
sample() {
    local phase="$1"
    local bytes
    bytes=($(dd if="$EC" bs=256 count=1 2>/dev/null | od -An -tu1 -v))
    echo "$(date +%s.%N | cut -c1-13),$phase,${bytes[62]},$((bytes[96]*256+bytes[97])),$((bytes[104]*256+bytes[105]))"
}

echo "time,phase,duty_0x3E,cpu_rpm_0x60BE16,gpu_rpm_0x68BE16" > "$OUT"
echo "logging to $OUT" >&2

log_for() { local phase="$1" secs="$2"; local end=$((SECONDS+secs)); while ((SECONDS<end)); do sample "$phase" >> "$OUT"; sleep 0.2; done; }

log_for baseline 4
ec_probe write 62 31; echo "wrote 0x3E=31" >&2
log_for write31 10
ec_probe write 62 78; echo "wrote 0x3E=78" >&2
log_for write78 10

echo "done: $OUT" >&2
