# EC register map — TongFang GK5NR0V (EVOO EG-LP7)

Reverse-engineered by observation and controlled experiments
(2026-09-15 first pass on PikaOS; 2026-09-19 revision on CachyOS; see
`docs/report.md` for the experiment log and `data/tests/` for raw captures.
Re-validated on kernel 7.2.7 on 2026-09-25 — see `docs/kernel7-session-20260925.md`.)
Access via `ec_sys` (`/sys/kernel/debug/ec/ec0/io`) or `ec_probe`.

## Confirmed / high confidence (2026-09-19 revision)

| Offset | Function | Evidence |
|---|---|---|
| `0x3E` | **CPU fan duty, 0–100%** | Firmware writes its own curve here (observed 45–98). External writes take physical effect in < 0.4 s; firmware reverts them within 0.2–0.6 s (re-measured 2026-09-25: 125–419 ms idle, 313–397 ms at load temps). Sustained control requires rewriting at ≥ 10 Hz (nbfc `EcPollInterval=100` → 90% dwell; `=50` → 96% dwell, phase-independent 20 Hz sampling) |
| `0x60`–`0x61` | **CPU fan RPM, 16-bit big-endian** | Constant 3272 RPM through a whole gaming session; in duty tests it tracked writes as a clean 266-RPM-step staircase, 316–3272 RPM. Full staircase observed: 316, 572, 848, 1114, 1380, 1646, 1912, 2178, 2444, 2720, 2996, 3272 |
| `0x68`–`0x69` | GPU fan RPM, 16-bit big-endian | Staircase 2178→2996 during game; 0 at idle (fan-stop); started exactly when dGPU core hit ~55 °C |
| `0x4C` | CPU-ish temperature | Correlates 0.705 with `k10temp` but reads lower (~15–20 °C offset); use `k10temp` for absolute values |
| `0x4B` | Performance/thermal state flag | 0 at desktop, 01/02 during gaming. **Not** a manual-mode gate: with `0x4B=1` written, firmware still reverted `0x3E` (modeflag test) |

## Fan duty response curve (2026-09-25 sweep)

Duty values below ~45 are a **dead zone**: the fan stalls/sputters at
0–316 RPM (sputter is acoustically worse than steady 572). Minimum
stable duty = 50. See `docs/kernel7-session-20260925.md` for the full
table and the k10temp single-sample Tctl spike warning (78→98 °C in
200 ms under background bursts — smooth before feeding a curve).

## GPU fan: no EC duty register exists

Under sustained dGPU load (2× nvenc + scale_cuda, core 48→73 °C), the GPU fan
spun 0→2996 RPM tracking the **dGPU core temperature** (nvidia-smi), while no
byte in the EC moved with it: `0x3F` stayed 0, `0x3E` was busy with the CPU,
and a full-register `ec_probe monitor` capture during load showed no candidate.
Conclusion: the GPU fan is driven by the dGPU's own controller (NVIDIA
fan-stop below ~55 °C core). The EC only mirrors its tachometer (`0x68–0x69`).
Thermal management for the GPU side = `nvidia-smi -pl` power capping.

## Demoted / corrected (earlier hypotheses that failed)

| Offset | Previous guess | Verdict |
|---|---|---|
| `0x65`, `0x6D` | CPU/2nd fan RPM (×10) | **Not tachs.** CPU tach at `0x60-61` sat rock-stable at 3272 RPM while these two jittered ±100 between samples — EC read-race artifacts |
| `0x49` | GPU temperature | **Not dGPU core temp**: read 6–25 °C while nvidia-smi reported 40–73 °C core. Some other GPU-side sensor (cold rail). Gaming readings 61–95 were coincidentally plausible; use nvidia-smi |
| `0x64`, `0x6C` | Fan duty candidates | Small temperature-ish values (10–22), never tracked duty |
| `0x3F` | GPU fan duty candidate | Hammered to 78 for 15 s: no fan movement, no firmware revert — register appears unused |
| `0xAD`, `0xAE` | (suspected temp during probing) | Seconds and minutes counters (`0xAD` wraps 59→0). Not temperatures |
| `0x34`–`0x35` | — | Slowly-decreasing 16-bit value (1003→612 across a fan ramp-down); battery-current-like, unknown |
| `0x0C`/`0x0E` | RPM (initial) | Unrelated (battery/power), never moved — unchanged verdict |
