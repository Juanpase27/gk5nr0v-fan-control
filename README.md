# gk5nr0v-fan-control

Recuperar el control de ventiladores de un **EVOO EG-LP7** (barebone TongFang
**GK5NR0V**, Ryzen 7 4800H + RTX 2060 Mobile) en Linux, tras perder el
software OEM de Windows (Tongfang Control Center). Documenta la ingeniería
inversa del Embedded Controller (EC), el mapa de registros identificados y el
camino con nbfc-linux.

> **Estado: parcialmente resuelto — sigue sin solucionarse del todo.**
> nbfc-linux corre y lee temperaturas reales, pero el efecto físico de los
> writes sobre los ventiladores en esta variante aún no está confirmado.
> Detalle completo en [`docs/report.md`](docs/report.md).

## Mapa EC (resumen)

| Offset | Función |
|---|---|
| `0x49` | Temperatura GPU (°C) |
| `0x4C` | Temperatura CPU (°C) |
| `0x68`–`0x69` | RPM fan GPU (BE16; 0 = fan-stop) |
| `0x65`, `0x6D` | Candidatos RPM fans CPU/2 (≈×10, jitter de taquímetro) |
| `0x4B` | Flag de modo de fan del firmware (01/02) |
| `0x3E` | Registro que escribe nbfc (config MECHREVO GK5NR0O, duty 31–78) — efecto físico sin confirmar en la variante -V |

Evidencia y capturas: [`docs/ec-register-map.md`](docs/ec-register-map.md) y
[`data/`](data/).

## Setup actual (reproducible)

```bash
# 1. EC accesible con escritura, persistente entre reinicios
sudo modprobe ec_sys write_support=1
echo ec_sys | sudo tee /etc/modules-load.d/ec_sys.conf
echo options ec_sys write_support=1 | sudo tee /etc/modprobe.d/ec_sys.conf

# 2. nbfc-linux 0.5.3 (Debian trixie build)
#    https://github.com/nbfc-linux/nbfc-linux/releases
sudo apt install -y ./debian-trixie-nbfc-linux_0.5.3_amd64.deb
#    En PikaOS, la dependencia acpi-call no compila (headers rotos):
#    ver docs/pikaos-headers-bug.md para el workaround con stub equivs.

# 3. Config del chasis hermano
sudo nbfc config --set "MECHREVO Jiaolong Series GK5NR0O"
sudo systemctl enable --now nbfc_service

# 4. Estado / control
nbfc status -a
sudo nbfc set -f 0 -s 100   # manual 100% (rampa ~3 s/paso)
sudo nbfc set -a            # volver a automático
```

## Herramientas del repo

- `scripts/ec-watch.sh` — monitor en vivo de las filas EC relevantes.
- `scripts/ec-dump.sh` — captura de dump EC con timestamp.
- `scripts/ec-diff.py` — diff byte a byte entre dos dumps.
- `data/` — capturas originales (idle, carga, juego) con procedencia.
- `config/` — config NBFC de referencia y stub equivs para PikaOS.

## Pendiente (roadmap)

- [ ] Test sostenido de `nbfc set -f 0 -s 100` (2 min) con watch del EC para
      confirmar/descartar que `0x3E` gobierna los fans en esta variante.
- [ ] Localizar el registro de duty real si el anterior falla (candidatos
      `0x64`, `0x6C`; flag de modo `0x4B`).
- [ ] Config NBFC propia dual-fan para el EG-LP7 y contribución upstream.
- [ ] Reportar bug de `linux-headers-7.2.4-pikaos` a PikaOS.
- [ ] Correlación térmica con `k10temp` / `nvidia-smi`.

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
