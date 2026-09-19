#!/usr/bin/env bash
# Sustained fan test for TongFang GK5NR0V / EVOO EG-LP7.
#
# Decides between scenarios A/B/C from docs/report.md:
#   A: nbfc writes to 0x3E DO drive the fans (previous test was cut short).
#   B: 0x3E writes have no physical effect on this variant.
#   C: a mode flag (0x4B?) must be toggled before duty writes take effect.
#
# Phases (1 Hz CSV log):
#   baseline  20 s  auto control (nbfc service running its curve)
#   manual100 120 s nbfc set -f 0 -s 100, held for the full ramp (~72 s) + margin
#   recovery  30 s  nbfc set -a (back to auto)
#
# Usage: sudo ./scripts/fan-test.sh [output_csv]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="/sys/kernel/debug/ec/ec0/io"

if [[ $EUID -ne 0 ]]; then
    echo "error: run as root (EC access requires it)" >&2
    exit 1
fi
if [[ ! -r "$EC" ]]; then
    echo "error: $EC not readable (modprobe ec_sys write_support=1)" >&2
    exit 1
fi

OUT="${1:-$REPO_ROOT/data/tests/fan_test_$(date +%Y%m%d_%H%M%S).csv}"
mkdir -p "$(dirname "$OUT")"

# Resolve hwmon inputs (k10temp = CPU Tctl, amdgpu = iGPU edge temp).
k10_input=""
gpu_input=""
for d in /sys/class/hwmon/hwmon*; do
    case "$(<"$d/name")" in
        k10temp) k10_input="$d/temp1_input" ;;
        amdgpu)  gpu_input="$d/temp1_input" ;;
    esac
done

# Decimal offsets per docs/ec-register-map.md.
# 62=0x3E duty | 75=0x4B mode flag | 73=0x49 GPU temp | 76=0x4C CPU temp
# 100/101=0x64/0x65 | 104/105=0x68/69 GPU fan RPM (BE16) | 108/109=0x6C/0x6D
sample() {
    local phase="$1"
    local bytes
    bytes=($(dd if="$EC" bs=256 count=1 2>/dev/null | od -An -tu1 -v))
    local duty=${bytes[62]} mode=${bytes[75]} gput=${bytes[73]} cput=${bytes[76]}
    local r64=${bytes[100]} r65=${bytes[101]} rhi=${bytes[104]} rlo=${bytes[105]}
    local r6c=${bytes[108]} r6d=${bytes[109]}
    local gpu_rpm=$((rhi * 256 + rlo))
    local k10="" gpuv=""
    [[ -n "$k10_input" ]] && k10=$(($(<"$k10_input") / 1000))
    [[ -n "$gpu_input" ]] && gpuv=$(($(<"$gpu_input") / 1000))
    echo "$(date +%s),$phase,$duty,$mode,$gput,$cput,$r64,$r65,$gpu_rpm,$r6c,$r6d,$k10,$gpuv"
}

log_phase() {
    local phase="$1" secs="$2"
    echo "--- phase $phase (${secs}s) ---" >&2
    for ((i = 0; i < secs; i++)); do
        sample "$phase" >> "$OUT"
        sleep 1
    done
}

echo "time,phase,duty_0x3E,mode_0x4B,gpu_t_0x49,cpu_t_0x4C,r0x64,cpu_rpm_x10_0x65,gpu_fan_rpm_0x68BE16,r0x6C,fan2_rpm_x10_0x6D,k10temp_c,igpu_c" > "$OUT"
echo "logging to $OUT" >&2

log_phase baseline 20

echo "--- snapshot before manual phase ---" >&2
hexdump -C "$EC" > "$OUT.pre.hexdump"
nbfc set -f 0 -s 100 >&2

log_phase manual100 120

echo "--- snapshot before recovery ---" >&2
hexdump -C "$EC" > "$OUT.mid.hexdump"
nbfc set -a >&2

log_phase recovery 30

hexdump -C "$EC" > "$OUT.post.hexdump"
echo "done: $OUT (+ .pre/.mid/.post hexdumps)" >&2
