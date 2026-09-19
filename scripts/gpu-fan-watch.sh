#!/usr/bin/env bash
# Observe which EC byte acts as the GPU-fan duty register, without writes:
# load the dGPU (ffmpeg nvenc encode + cuda scale) and log the whole EC row
# 0x30 plus both tachs at 2 Hz. The byte that jumps when the GPU fan spins
# (tach 0x68-0x69 leaves 0) is the GPU duty.
#
# Usage: sudo ./scripts/gpu-fan-watch.sh [encode_seconds]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EC="/sys/kernel/debug/ec/ec0/io"
OUT="$REPO_ROOT/data/tests/gpu_watch_$(date +%Y%m%d_%H%M%S).csv"
SECS="${1:-150}"

if [[ $EUID -ne 0 ]]; then echo "error: run as root" >&2; exit 1; fi

sample() {
    local phase="$1"
    local bytes row30 rowA0
    bytes=($(dd if="$EC" bs=256 count=1 2>/dev/null | od -An -tu1 -v))
    row30=$(printf '%02x' "${bytes[@]:48:16}" | tr -d '\n')
    rowA0=$(printf '%02x' "${bytes[@]:160:16}" | tr -d '\n')
    local smi gpu_t gpu_p
    smi=$(nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    gpu_t=${smi%,*}; gpu_p=${smi#*,}
    echo "$(date +%s),$phase,$row30,$rowA0,${bytes[73]},$((bytes[96]*256+bytes[97])),$((bytes[104]*256+bytes[105])),$gpu_t,$gpu_p"
}

echo "time,phase,row30_hex,rowA0_hex,ec_gpu_t_0x49,cpu_rpm_0x60BE16,gpu_rpm_0x68BE16,nv_temp,nv_power_w" > "$OUT"
echo "logging to $OUT" >&2

log_for() { local phase="$1" secs="$2"; local end=$((SECONDS+secs)); while ((SECONDS<end)); do sample "$phase" >> "$OUT"; sleep 0.5; done; }

log_for baseline 20
echo "starting ${SECS}s nvenc load (2 parallel instances)" >&2
for j in 1 2; do
    ffmpeg -hide_banner -loglevel error -init_hw_device cuda=cu:0 -filter_hw_device cu \
        -f lavfi -i "testsrc2=size=1920x1080:rate=60" -t "$SECS" \
        -vf "hwupload,scale_cuda=3840:2160" -c:v h264_nvenc -preset p1 -b:v 50M \
        -f null - 2>/dev/null || true &
done
log_for load "$SECS"
wait
log_for cooldown 90
echo "done: $OUT" >&2
