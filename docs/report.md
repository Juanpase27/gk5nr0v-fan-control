# Reporte de estado — control de ventiladores EVOO EG-LP7 (GK5NR0V)

Fecha: 2026-09-15 (PikaOS) · **Actualizado 2026-09-19 (CachyOS): RESUELTO
para el fan CPU** · El fan GPU resultó no ser controlable por EC (ver abajo).

## TL;DR

- **Fan CPU: control completo** vía EC `0x3E` (duty 0–100%). El firmware
  reescribe el registro cada ~0.2–0.6 s con su propia curva, así que hay que
  reescribirlo a ≥10 Hz. La config NBFC propia `EVOO EG-LP7 (TongFang GK5NR0V)`
  con `EcPollInterval=100` gana esa pelea y queda instalada como servicio.
- **Fan GPU: no hay registro de duty en el EC** — lo gobierna el controlador
  de la propia dGPU (fan-stop hasta ~55 °C de núcleo). El EC solo refleja su
  tacómetro. Manejo térmico GPU = `nvidia-smi -pl`.
- `0x4B` NO es un gate de modo manual (probado). Tacómetro CPU real:
  `0x60–0x61` BE16. `0x49` NO es la temperatura del núcleo dGPU.

## Contexto

El equipo (EVOO EG-LP7, barebone TongFang GK5NR0V, Ryzen 7 4800H + RTX 2060
Mobile) vino con Windows y el software OEM (Tongfang Control Center) ya no
está disponible. Objetivo: recuperar control de ventiladores (lectura RPM +
curvas) en Linux. El chasis no expone `fan*`/`pwm*` en hwmon: todo va por EC.

## Log de experimentos 2026-09-19 (CachyOS, kernel 7.2.6)

Todo el material bruto está en `data/tests/` (ver README allí).

1. **Test sostenido nbfc@3 s** (`fan_test_*.csv`): con la config MECHREVO
   (poll 3 s), `nbfc set -s 100` sostenido 120 s no sostiene el duty:
   `0x3E` fluctuó 55–80 y la correlación duty↔RPM fue 0.108. Pero `0x3E`
   correlaciona +0.78 con k10temp → es el registro que alimenta el firmware,
   que llega hasta 96–98 bajo carga. Escenario A (la config tal cual funciona)
   descartado; escenario B (write inefectivo) también: ver 2.
2. **Latencia de reversión** (`write_latency_*.csv`, nbfc parado): escribir
   `0x3E=31` directo → el fan CPU cayó 848→316 RPM en 0.4 s; el firmware lo
   revirtió en <0.6 s (31→46→53→57…). Escribir `0x3E=78` → 2178 RPM
   inmediato, decayendo al revertir. **Control físico confirmado.**
3. **Hammer POC** (`hammer_*.csv`): reescribir `0x3E=78` cada 100 ms durante
   20 s → duty clavado en 78, tach estable en 2178 RPM; al soltar, el
   firmware caminó 78→48 y el fan bajó a 316 RPM. **10 Hz gana la pelea.**
4. **Gate de modo** (`modeflag_*.csv`): con `0x4B=1` escrito, el firmware
   siguió revirtiendo `0x3E=40` igual → `0x4B` no es el interruptor de modo
   manual (parece flag de estado/perfil: 0 escritorio, 01/02 en juego).
5. **Sondeo GPU duty** (`gpu_duty_probe_*.csv`): `0x3F` martillado a 78
   15 s → el fan GPU ni se movió y el firmware ni revertió el registro
   (parece no usado). Desviación documentada de la regla "solo valores
   observados", sin efectos colaterales (diffs pre/post solo térmicos).
6. **Carga dGPU observacional** (`gpu_watch_*.csv`, `ec_monitor_gpu_load*.txt`):
   2× nvenc + scale_cuda llevaron el núcleo de 48→73 °C; el fan GPU arrancó
   exactamente a ~55 °C y escaló hasta 2996 RPM **sin que ningún byte del EC
   lo acompañara** (`0x3F`=0 fijo; monitor completo de 256 bytes sin candidato).
   Veredicto: fan GPU gobernado por la dGPU, no por EC.
7. **Config propia @100 ms** (`nbfc100ms_hold.csv`): config NBFC
   `EVOO EG-LP7 (TongFang GK5NR0V)` (duty 25–100, curva k10temp, Critical 92 °C):
   `nbfc set -s 70` sostuvo duty=78 en 110/120 muestras y tach=2178 RPM estable.
   **Solución nativa confirmada** — sin daemon externo.

## Setup vigente en el equipo (CachyOS, reproducible)

```bash
# 1. EC accesible (persistente entre reinicios)
sudo modprobe ec_sys write_support=1
echo ec_sys | sudo tee /etc/modules-load.d/ec_sys.conf
echo options ec_sys write_support=1 | sudo tee /etc/modprobe.d/ec_sys.conf

# 2. nbfc-linux (paquete oficial para Arch; CachyOS = pacman -U)
#    https://github.com/nbfc-linux/nbfc-linux/releases (arch-linux-*.pkg.tar.zst)
sudo pacman -U --needed arch-linux-nbfc-linux-git-0.5.3-1-x86_64.pkg.tar.zst

# 3. Config propia del chasis (este repo)
sudo cp config/evoo-eg-lp7-gk5nr0v.json \
    "/usr/share/nbfc/configs/EVOO EG-LP7 (TongFang GK5NR0V).json"
sudo nbfc config --set "EVOO EG-LP7 (TongFang GK5NR0V)"
sudo systemctl enable --now nbfc_service

# 4. Uso
nbfc status -a
sudo nbfc set -f 0 -s 70    # manual 70% (duty ≈ 77)
sudo nbfc set -a            # volver a la curva automática
```

La clave frente a la config MECHREVO heredada: `EcPollInterval: 100` (vs 3000)
y rango 25–100 (vs 31–78). El poll de 3 s perdía siempre contra el firmware.

## Riesgos y salvaguardas

- Escribir registros EC desconocidos puede afectar teclado/batería/gestión
  térmica. Regla del proyecto: solo valores dentro de rangos ya observados,
  un registro a la vez, con dump previo y posterior. La única desviación
  documentada: el sondeo `0x3F=78` (experimento 5), sin efectos.
- NBFC mantiene Critical Mode (100% forzado a 92 °C) incluso en manual.
- Reescribir `0x3E` a 10 Hz es lo que hacía de facto el software OEM; sin
  evidencia de desgaste, pero se documenta el mecanismo.

## Pendiente (roadmap)

- [x] Confirmar efecto físico de `0x3E` (hecho: control completo CPU).
- [x] Tacómetro CPU fiable (`0x60-61` BE16).
- [x] Localizar duty GPU → no existe en el EC (dGPU-driven).
- [x] Config NBFC propia para el EG-LP7 funcionando.
- [ ] Contribuir la config upstream al repo de configs de nbfc-linux.
- [ ] Curva afinada con uso real (los umbrales actuales son un primer
      borrador conservador; k10temp idle de este equipo es alto, 60–75 °C).
- [x] ~~Reportar bug de headers de PikaOS~~ (obsoleto: el proyecto migró a
      CachyOS, donde las dependencias están en repos y no hubo que compilar).
- [x] Correlación térmica: `0x4C`↔k10temp (+0.705, offset ~15–20 °C);
      dGPU core = solo nvidia-smi (`0x49` no es el núcleo).
