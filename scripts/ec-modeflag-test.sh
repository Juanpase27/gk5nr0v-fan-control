#!/usr/bin/env bash
# Test whether EC 0x4B (observed values 0/1/2) gates the firmware's automatic
# fan-control loop on the GK5NR0V.
#
# With nbfc stopped: write 0x4B=1, then a single 0x3E=40 (low, within the
# range nbfc itself wrote today). If 0x3E stays at 40 without hammering,
# 0x4B is the manual-mode gate. Reverts both registers and restarts nbfc.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="/sys/kernel/debug/ec/ec0/io"
OUT="$REPO_ROOT/data/tests/modeflag_$(date +%Y%m%d_%H%M%S).csv"

if [[ $EUID -ne 0 ]]; then echo "error: run as root" >&2; exit 1; fi

# duty=62(0x3E) mode=75(0x4B) | cpu tach 96,97 | gpu tach 104,105
sample() {
    local phase="$1"
    local bytes
    bytes=($(dd if="$EC" bs=256 count=1 2>/dev/null | od -An -tu1 -v))
    echo "$(date +%s.%N | cut -c1-13),$phase,${bytes[62]},${bytes[75]},$((bytes[96]*256+bytes[97])),$((bytes[104]*256+bytes[105]))"
}

systemctl stop nbfc_service
trap 'ec_probe write 75 0 2>/dev/null || true; systemctl start nbfc_service' EXIT
echo "logging to $OUT" >&2
echo "time,phase,duty_0x3E,mode_0x4B,cpu_rpm_0x60BE16,gpu_rpm_0x68BE16" > "$OUT"

log_for() { local phase="$1" secs="$2"; local end=$((SECONDS+secs)); while ((SECONDS<end)); do sample "$phase" >> "$OUT"; sleep 0.2; done; }

hexdump -C "$EC" > "$OUT.pre.hexdump"
log_for baseline 5
ec_probe write 75 1
echo "wrote 0x4B=1" >&2
log_for mode1 5
ec_probe write 62 40
echo "wrote 0x3E=40 with 0x4B=1" >&2
log_for mode1_duty40 12
ec_probe write 75 0
echo "reverted 0x4B=0" >&2
log_for reverted 8
hexdump -C "$EC" > "$OUT.post.hexdump"
echo "done: $OUT" >&2
