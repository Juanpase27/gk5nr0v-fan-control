#!/usr/bin/env bash
# One-shot sensor readout for the gk5nr0v-fans Caelestia plugin.
# Prints key=value lines; missing sensors are skipped silently so the
# widget degrades gracefully (e.g. module not loaded, dGPU asleep).
#
# Usage: read-sensors.sh [gpu]   -- "gpu" adds an nvidia-smi core temp query
set -u

hwmon_by_name() {
    local f
    for f in /sys/class/hwmon/hwmon*/name; do
        [[ -r "$f" ]] || continue
        if [[ "$(cat "$f" 2>/dev/null)" == "$1" ]]; then
            dirname "$f"
            return 0
        fi
    done
    return 1
}

fans=$(hwmon_by_name gk5nr0v_fans) || true
k10=$(hwmon_by_name k10temp) || true

if [[ -n "${fans:-}" ]]; then
    echo "cpu_rpm=$(cat "$fans/fan1_input" 2>/dev/null || echo 0)"
    echo "gpu_rpm=$(cat "$fans/fan2_input" 2>/dev/null || echo 0)"
fi

if [[ -n "${k10:-}" && -r "$k10/temp1_input" ]]; then
    awk 'END { printf "cpu_t=%.1f\n", $1/1000 }' "$k10/temp1_input"
fi

if [[ "${1:-}" == "gpu" ]]; then
    # nvidia-smi briefly wakes the dGPU; only called every 5 s on purpose.
    t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
    [[ -n "$t" ]] && echo "gpu_t=$t"
fi
