# Data provenance

All captures taken on 2026-09-15 from `/sys/kernel/debug/ec/ec0/io` (256 bytes)
with `ec_sys` loaded, on an EVOO EG-LP7 (TongFang GK5NR0V, Ryzen 7 4800H,
RTX 2060 Mobile) running PikaOS 4 (kernel 7.2.4-pikaos).

Original files lived in `/tmp` and were lost after a reboot; the contents here
were recovered verbatim from the recorded session output. Byte values are
exactly as captured.

| File | Conditions |
|---|---|
| `ec_dump_idle.txt` | Idle, ~45 °C CPU. Full 256-byte dump (hexdump -C). |
| `ec_dump_short_load.txt` | ~30 s of light load (dump taken too early for fans to ramp). |
| `ec_stress60s_vs_idle.diff` | Byte-level diff idle vs after 60 s of `stress-ng --cpu 16`. |
| `ec_game_watch_excerpt.txt` | `watch -n2` excerpts (rows 0x40/0x60) during a gaming session; last samples after closing the game. |
