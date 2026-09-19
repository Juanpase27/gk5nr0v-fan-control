# data/tests — captures from the 2026-09-19 experiment session (CachyOS)

All captured on the same EVOO EG-LP7 (GK5NR0V) running CachyOS, kernel
7.2.6-1-cachyos. EC read via `/sys/kernel/debug/ec/ec0/io` (`ec_sys` loaded
with write support) unless noted. Sampling scripts live in `../../scripts/`.

| File | Experiment | Key result |
|---|---|---|
| `fan_test_20260919_141508.csv` (+ `.pre/.mid/.post.hexdump`) | Sustained 120 s `nbfc set -s 100` with MECHREVO config (3 s poll), 1 Hz log | duty 0x3E fluctuates 55–80; corr(duty,RPM)=0.108; corr(duty,k10temp)=+0.78 → firmware owns 0x3E |
| `write_latency_20260919_142557.csv` | Direct single writes to 0x3E (nbfc stopped), 5 Hz log | 0x3E=31 → CPU fan 848→316 RPM in 0.4 s; firmware reverts <0.6 s. 0x3E=78 → 2178 RPM |
| `hammer_20260919_142840.csv` | 0x3E=78 rewritten every 100 ms for 20 s | duty pinned at 78, tach steady 2178 RPM; on release firmware walks 78→48, fan →316 RPM |
| `modeflag_20260919_143005.csv` (+ `.pre/.post.hexdump`) | 0x4B=1 written, then 0x3E=40 | firmware still reverts 0x3E → 0x4B is not a manual-mode gate |
| `gpu_duty_probe_20260919_143103.csv` (+ `.pre/.post.hexdump`) | 0x3F hammered to 78 for 15 s | GPU fan unmoved, register not firmware-managed → 0x3F unused (documented deviation from observed-values-only rule) |
| `gpu_watch_20260919_143247.csv` | (failed run: load never ran, logging gap) | kept for completeness |
| `gpu_watch_20260919_143523.csv` | 2× nvenc load, row 0x30 @2 Hz | GPU fan starts at nvT≈55 °C; no row-0x30 byte tracks it |
| `ec_monitor_gpu_load.txt`, `ec_monitor_gpu_load2.txt` | full 256-byte `ec_probe monitor` during GPU load (ANSI-colored output as produced) | no register moves with the GPU fan; 0xAD/0AE are seconds/minutes counters |
| `gpu_watch_20260919_144713.csv` | 2× nvenc load, rows 0x30+0xA0 @2 Hz, fan spun to 2996 RPM | definitive: GPU fan follows dGPU core temp, no EC duty register |
| `nbfc100ms_hold.csv` | custom config (EcPollInterval=100), `nbfc set -s 70`, 30 s | duty=78 in 110/120 samples, tach steady 2178 RPM → native nbfc control works |
