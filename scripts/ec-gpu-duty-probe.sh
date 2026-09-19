#!/usr/bin/env bash
# Probe EC 0x3F as the GPU-fan duty register on the GK5NR0V.
#
# Documented deviation from the "observed values only" rule: 0x3F has only
# ever been observed as 0x00 (GPU idle, fan-stop). We hammer it at 78 (a duty
# value already exercised on the adjacent CPU duty register 0x3E today) for
# 15 s max, watch the GPU tach (0x68-0x69 BE16), then release and force-revert
# to 0 if the firmware does not do it by itself. Dumps before/after.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="/sys/kernel/debug/ec/ec0/io"
OUT="$REPO_ROOT/data/tests/gpu_duty_probe_$(date +%Y%m%d_%H%M%S).csv"

if [[ $EUID -ne 0 ]]; then echo "error: run as root" >&2; exit 1; fi

# cpu duty=62 | gpu duty candidate=63(0x3F) | cpu tach 96,97 | gpu tach 104,105
sample() {
    local phase="$1"
    local bytes
    bytes=($(dd if="$EC" bs=256 count=1 2>/dev/null | od -An -tu1 -v))
    echo "$(date +%s.%N | cut -c1-13),$phase,${bytes[62]},${bytes[63]},$((bytes[96]*256+bytes[97])),$((bytes[104]*256+bytes[105]))"
}

systemctl stop nbfc_service
trap 'ec_probe write 63 0 2>/dev/null || true; systemctl start nbfc_service' EXIT
echo "logging to $OUT" >&2
echo "time,phase,cpu_duty_0x3E,gpu_duty_0x3F,cpu_rpm_0x60BE16,gpu_rpm_0x68BE16" > "$OUT"

log_for() { local phase="$1" secs="$2"; local end=$((SECONDS+secs)); while ((SECONDS<end)); do sample "$phase" >> "$OUT"; sleep 0.2; done; }

hexdump -C "$EC" > "$OUT.pre.hexdump"
log_for baseline 4
echo "hammering 0x3F=78 every 100 ms for 15 s" >&2
for ((i = 0; i < 150; i++)); do
    ec_probe write 63 78
    if ((i % 2 == 0)); then sample hammer3F >> "$OUT"; fi
    sleep 0.1
done
log_for released 10
hexdump -C "$EC" > "$OUT.post.hexdump"
echo "done: $OUT" >&2
