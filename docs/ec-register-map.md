# EC register map — TongFang GK5NR0V (EVOO EG-LP7)

Reverse-engineered by observation (idle / stress-ng / gaming dumps, 2026-09-15).
Access via `ec_sys` (`/sys/kernel/debug/ec/ec0/io`, 256 bytes).
See `data/README.md` for capture conditions.

## Confirmed / high confidence

| Offset | Function | Evidence |
|---|---|---|
| `0x49` | GPU temperature (°C) | ~30 idle → 95 peak during game, 22 after closing it |
| `0x4C` | CPU temperature (°C) | follows thermal curve under load (60 → 110+ readings include EC read-race artifacts; correlate with `k10temp` before trusting absolute values) |
| `0x68`–`0x69` | GPU fan RPM, 16-bit big-endian | perfect arithmetic staircase during game: 0x0882=2178 → 0x098C=2444 → 0x0AA0=2720 → 0x0BB4=2996 RPM; zero at idle (fan-stop) |
| `0x4B` | Firmware fan mode flag | toggles 01/02 between samples |

## Candidates (moved with load, encoding not fully confirmed)

| Offset | Candidate function | Observed values |
|---|---|---|
| `0x65` | CPU/system fan RPM (~value × 10) | tachometer-like jitter: 148–195 (≈1480–1950 RPM) |
| `0x6D` | Second fan RPM (~value × 10) | jitter 138–181 |
| `0x64`, `0x6C` | Fan duty or secondary thermal sensor | static 19–22 regardless of fan ramp — not the duty register |
| `0x3E` | NBFC write register (from MECHREVO GK5NR0O config: decimal 62, duty 31–78) | NBFC reads/writes it; physical effect on fans still unverified on the -V variant |

## Notes

- Registers `0x0C`/`0x0E` (LE16 0x0226 = 550) were initially suspected as RPM but never moved; likely unrelated (battery/power).
- Fan control on this chassis is EC-mediated (no `hwmon` fan/pwm exposed).
- The OEM Windows software was the Tongfang "Control Center"; it drove the same EC.
- Next step to finish the map: sustained `nbfc set -f 0 -s 100` for ~2 min while watching whether `0x3E` changes correlate with RPM (`0x65`, `0x68-69`) and audible fan speed.
