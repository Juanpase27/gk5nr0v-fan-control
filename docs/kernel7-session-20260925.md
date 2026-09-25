# Kernel 7 validation session — 2026-09-25

Re-applied and re-validated the whole stack on the fresh CachyOS install
(kernel **7.2.7-1-cachyos**) after the machine was rebuilt from a base
image. Everything below was measured the same day; raw captures in
`data/tests/*_20260925_*.csv`.

## Environment

- CachyOS base, kernel 7.2.7-1-cachyos, on AC power, screen locked,
  desktop session + z-code client running in background (realistic
  continuous light load: CPU 55-85 °C swings).
- `ec_sys` loaded with `write_support=1`, made persistent via
  `/etc/modules-load.d/ec_sys.conf` + `/etc/modprobe.d/ec_sys.conf`.
- nbfc-linux 0.5.3 (official Arch package from the 0.5.3 release).

## ec_sys on kernel 7.x

The kernel 6.13+ ec_sys exposes ONLY `/sys/kernel/debug/ec/ec0/io`
(the old 256-byte `ram` blob file is gone). `io` is offset-addressed:
file position == EC address; reads/writes are one `ec_read`/`ec_write`
transaction per byte. Writes return EINVAL unless `write_support=1`.
`os.pread`/`os.pwrite` is the natural userspace API (see
`scripts/ec-fan-driver.py`). This is what the 2026-09-19 scripts already
used, so nothing needed porting.

## Measured behavior (all 2026-09-25)

- **Firmware revert latency**: 125-419 ms idle, 313-397 ms at load temps.
  Unchanged vs. the original findings.
- **Fan duty → RPM map** (sweep, 25 s per step, `sweep_20260925_110837.csv`):

  | duty (EC 0x3E) | RPM (tach staircase) | note |
  |---|---|---|
  | < 45 | 0 - 316 | **dead zone — fan stalls/sputters** |
  | 50 - 60 | 572 - 848 | minimum stable spin |
  | 70 | 1380 - 1646 | |
  | 80 | 2178 - 2444 | |
  | 98 (firmware max observed) | 3272 (2026-09-15 data) | |

  Full observed tach staircase (+266 RPM steps): 316, 572, 848, 1114,
  1380, 1646, 1912, 2178, 2444, 2720, 2996, 3272.

- **k10temp single-sample spikes**: Tctl jumped 78→98 °C in 200 ms under
  a background burst (screen locker / client rendering). Curve logic must
  smooth (median of 2-3 reads) or it will overreact; hard guards should
  still trip on a spike (cheap release, firmware reclaims in < 1 s).
- **Honest control measurement**: sampling the duty register right after
  your own write overstates control (you read yourself). Phase-independent
  sampling at 20 Hz is the honest metric:
  - 10 Hz rewrite (EcPollInterval=100): **90% dwell** at commanded value
  - 20 Hz rewrite (EcPollInterval=50): **96% dwell**, band-exact
- The fan's inertia (hundreds of ms) makes 90% register dwell enough for
  stable physical control, but 50 ms poll costs nothing (EC transactions
  are ~0.5 ms) and buys margin.

## nbfc-linux 0.5.3 quirks found today

1. **Manual mode (`nbfc set -f 0 -s N`) writes once** (write-on-change),
   so the firmware reverts it in < 0.5 s. Manual fixed-speed against this
   firmware needs a continuous rewriter — use
   `scripts/ec-fan-driver.py hold <duty> <secs>` instead.
2. **State bug**: after manual-mode commands or rapid stop/start cycles,
   the service sometimes stops writing periodically while `nbfc status`
   still shows Auto Control Enabled and sane targets (observed: flat-50
   config test with 1% dwell). `systemctl restart nbfc_service` restores
   the write loop. After any manual command, restart the service.
3. Config validation: an `UpThreshold` above `CriticalTemperature` logs a
   warning and degrades the controller. Keep every UpThreshold ≤
   CriticalTemperature (v2 uses CriticalTemperature 97, max Up 95).

## Config v2 (`config/evoo-eg-lp7-gk5nr0v-v2.json`)

Curve rebuilt from today's duty-RPM characterization, in EC-value space
via `MinSpeedValue=50 / MaxSpeedValue=100` (write = 50 + speed%/2):

| k10temp | speed% | EC write | RPM |
|---|---|---|---|
| < 60 | 0 | 50 | 572 |
| 60-68 | 20 | 60 | 848 |
| 68-75 | 40 | 70 | 1380 |
| 75-82 | 60 | 80 | 2178 |
| 82-88 | 85 | 92 | ~3000 |
| > 88 | 100 | 100 | ~3300 |

Plus `EcPollInterval=50`, `CriticalTemperature=97`, hysteresis built into
nbfc Up/Down thresholds (v1 had a dead-zone bug: its low bands wrote
EC 25-51 where the fan stalls — sputter noise).

Result vs. stock firmware under the same background load:
firmware median duty 71 / 1646 RPM; v2 median EC 50-60 / **572-848 RPM**
at ~+4-8 °C. Trade accepted: that is the point of the project.

## Tooling

`scripts/ec-fan-driver.py` — python driver, native kernel-7 `io` access:

```
watch <secs> <hz>          # passive telemetry to CSV
latency <vals_csv>         # single-write revert timing
hold <duty> <secs>         # manual fixed speed at 10 Hz (for tests)
sweep <duties_csv> <secs>  # duty → RPM characterization
curve <spec> <secs>        # curve engine w/ hysteresis + temp smoothing
```

Curve spec `"50:62,58:69,66:75,76:82,90:130"` = duty until k10temp °C.
The demo run (before nbfc was reinstalled) held 96%+ dwell with the
guard never tripping after adding median smoothing.
