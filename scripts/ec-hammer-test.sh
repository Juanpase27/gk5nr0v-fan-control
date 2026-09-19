#!/usr/bin/env bash
# Proof-of-concept: hold EC 0x3E (CPU fan duty) at 78 by rewriting it every
# 100 ms, faster than the firmware control loop (~0.2-0.6 s revert measured).
# Logs duty + both tachs at 5 Hz throughout.
#
# Usage (nbfc service gets stopped/started automatically):
#   sudo ./scripts/ec-hammer-test.sh [duty_value 0-100] [hold_seconds]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="/sys/kernel/debug/ec/ec0/io"
OUT="$REPO_ROOT/data/tests/hammer_$(date +%Y%m%d_%H%M%S).csv"
DUTY="${1:-78}"
HOLD="${2:-20}"

if [[ $EUID -ne 0 ]]; then echo "error: run as root" >&2; exit 1; fi

# decimal offsets: duty=62(0x3E) | cpu tach 96,97 | gpu tach 104,105
sample() {
    local phase="$1"
    local bytes
    bytes=($(dd if="$EC" bs=256 count=1 2>/dev/null | od -An -tu1 -v))
    echo "$(date +%s.%N | cut -c1-13),$phase,${bytes[62]},$((bytes[96]*256+bytes[97])),$((bytes[104]*256+bytes[105]))"
}

systemctl stop nbfc_service
trap 'systemctl start nbfc_service' EXIT
echo "logging to $OUT" >&2
echo "time,phase,duty_0x3E,cpu_rpm_0x60BE16,gpu_rpm_0x68BE16" > "$OUT"

log_for() { local phase="$1" secs="$2"; local end=$((SECONDS+secs)); while ((SECONDS<end)); do sample "$phase" >> "$OUT"; sleep 0.2; done; }

log_for baseline 4
echo "hammering 0x3E=$DUTY every 100 ms for ${HOLD}s" >&2
for ((i = 0; i < HOLD * 10; i++)); do
    ec_probe write 62 "$DUTY"
    if ((i % 2 == 0)); then sample hammer >> "$OUT"; fi
    sleep 0.1
done
log_for released 10
echo "done: $OUT" >&2
