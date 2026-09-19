# gk5nr0v-fan-control

Recuperar el control de ventiladores de un **EVOO EG-LP7** (barebone TongFang
**GK5NR0V**, Ryzen 7 4800H + RTX 2060 Mobile) en Linux, tras perder el
software OEM de Windows (Tongfang Control Center). Documenta la ingeniería
inversa del Embedded Controller (EC), el mapa de registros y el camino con
nbfc-linux.

> **Estado: RESUELTO para el fan CPU (2026-09-19).** Control completo vía
> config NBFC propia (`EcPollInterval=100`). El fan GPU resultó **no tener
> registro de duty en el EC** — lo gobierna la propia dGPU (fan-stop hasta
> ~55 °C de núcleo); el EC solo refleja su tacómetro. Detalle completo en
> [`docs/report.md`](docs/report.md).

## Mapa EC (resumen)

| Offset | Función |
|---|---|
| `0x3E` | **Duty del fan CPU (0–100%)** — el firmware lo reescribe cada 0.2–0.6 s; control efectivo reescribiendo a ≥10 Hz |
| `0x60`–`0x61` | RPM fan CPU (BE16; escalera de pasos de 266 RPM) |
| `0x68`–`0x69` | RPM fan GPU (BE16; 0 = fan-stop, arranca a ~55 °C de núcleo dGPU) |
| `0x4C` | Temperatura CPU "del EC" (correlaciona con k10temp, lee ~15–20 °C menos) |
| `0x4B` | Flag de estado/perfil (0 escritorio, 01/02 juego) — **no** es gate de modo manual (probado) |

Correcciones importantes vs. la primera pasada: `0x65`/`0x6D` **no** son
tacómetros (ruido de lectura), `0x49` **no** es la temperatura del núcleo
dGPU (usar `nvidia-smi`), y `0xAD`/`0xAE` son contadores de segundos/minutos.
Mapa completo y veredictos: [`docs/ec-register-map.md`](docs/ec-register-map.md).

## Setup (CachyOS/Arch, reproducible)

```bash
# 1. EC accesible con escritura, persistente entre reinicios
sudo modprobe ec_sys write_support=1
echo ec_sys | sudo tee /etc/modules-load.d/ec_sys.conf
echo options ec_sys write_support=1 | sudo tee /etc/modprobe.d/ec_sys.conf

# 2. nbfc-linux 0.5.3 (paquete oficial para Arch)
#    https://github.com/nbfc-linux/nbfc-linux/releases
sudo pacman -U --needed arch-linux-nbfc-linux-git-0.5.3-1-x86_64.pkg.tar.zst

# 3. Config propia del chasis (ESTE repo) y servicio
sudo cp config/evoo-eg-lp7-gk5nr0v.json \
    "/usr/share/nbfc/configs/EVOO EG-LP7 (TongFang GK5NR0V).json"
sudo nbfc config --set "EVOO EG-LP7 (TongFang GK5NR0V)"
sudo systemctl enable --now nbfc_service

# 4. Estado / control
nbfc status -a
sudo nbfc set -f 0 -s 70   # manual 70% (duty ≈ 77)
sudo nbfc set -a           # volver a automático
```

La clave de la config propia frente a la heredada (MECHREVO GK5NR0O):
`EcPollInterval: 100` en vez de 3000 — con 3 s el firmware siempre gana; con
100 ms nbfc sostiene el duty (verificado: duty=78 en 110/120 muestras con
tach estable, `data/tests/nbfc100ms_hold.csv`).

Nota PikaOS (histórico): en PikaOS 4 la dependencia `acpi_call` no compilaba
(headers rotos); workaround en `docs/pikaos-headers-bug.md`. En CachyOS las
dependencias están en repos y no hubo que compilar nada.

## Herramientas del repo

- `scripts/ec-watch.sh` — monitor en vivo de las filas EC relevantes.
- `scripts/ec-dump.sh` — captura de dump EC con timestamp.
- `scripts/ec-diff.py` — diff byte a byte entre dos dumps.
- `scripts/fan-test.sh` — test sostenido con logging CSV (fases auto/manual/auto).
- `scripts/ec-write-latency.sh` — mide cuánto tarda el firmware en revertir un write.
- `scripts/ec-hammer-test.sh` — POC de control reescribiendo el duty a 10 Hz.
- `scripts/ec-modeflag-test.sh` — test del gate de modo (0x4B).
- `scripts/ec-gpu-duty-probe.sh` — sondeo del candidato a duty GPU (0x3F).
- `scripts/gpu-fan-watch.sh` — observación del fan GPU bajo carga dGPU (nvenc).
- `config/evoo-eg-lp7-gk5nr0v.json` — **config NBFC propia (la solución)**.
- `config/nbfc-mechrevo-gk5nr0o-reference.json` — config hermana de referencia.
- `data/` — capturas 2026-09-15; `data/tests/` — sesión experimental 2026-09-19.

## Pendiente (roadmap)

- [ ] Contribuir `evoo-eg-lp7-gk5nr0v.json` upstream al repo de configs de nbfc-linux.
- [ ] Afinar la curva con uso real (primer borrador conservador).
- [ ] (Opcional) capped térmico del lado GPU vía `nvidia-smi -pl`.

## Referencias

- [nbfc-linux](https://github.com/nbfc-linux/nbfc-linux) — fork mantenido de
  NoteBook FanControl (GPLv3).
- [ArchWiki — Fan speed control](https://wiki.archlinux.org/title/Fan_speed_control)
- [r/EVOOGaming](https://www.reddit.com/r/EVOOGaming/) — comunidad del
  EG-LP7 y la plataforma GK5NR0V (compartida con Maingear Vector 15).

## Licencia

MIT. Los dumps y hallazgos son de dominio práctico; úsalos bajo tu propio
riesgo — escribir en el EC de un portátil puede tener efectos no deseados
(lee `docs/report.md`, sección riesgos).
