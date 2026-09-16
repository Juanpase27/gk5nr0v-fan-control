# Reporte de estado — control de ventiladores EVOO EG-LP7 (GK5NR0V)

Fecha: 2026-09-15 · Estado: **PARCIALMENTE RESUELTO — sigue sin solucionarse del todo**

## Contexto

El equipo (EVOO EG-LP7, barebone TongFang GK5NR0V, Ryzen 7 4800H + RTX 2060
Mobile) vino con Windows y el software OEM de gestión (Tongfang Control
Center) ya no está disponible. Objetivo: recuperar control de ventiladores
(lectura RPM + curvas) en Linux (PikaOS 4).

El chasis no expone ningún `fan*`/`pwm*` en hwmon: el control es exclusivamente
vía Embedded Controller (EC), igual que hacía el software OEM.

## Lo conseguido hasta ahora

1. **Acceso al EC operativo y persistente**: `ec_sys` con `write_support=1`
   (`/etc/modules-load.d/ec_sys.conf` + `/etc/modprobe.d/ec_sys.conf`).
2. **Mapa EC parcial** (ver `docs/ec-register-map.md`): temperaturas GPU/CPU
   identificadas, RPM del fan de GPU confirmado (BE16 en `0x68-0x69`,
   escalera 2178→2996 RPM durante juego), candidatos de RPM de CPU.
3. **nbfc-linux 0.5.3 instalado y corriendo** con la config
   `MECHREVO Jiaolong Series GK5NR0O` (mismo barebone, variante -O):
   - Lee temperatura real (coincide con rangos observados).
   - Auto-control activo: escribe en el registro 62 decimal (`0x3E`),
     duty 31–78, rampeando un paso cada `EcPollInterval` (3 s).
   - Salida de `nbfc status -a`: Temperature 62–67 °C, Current Fan Speed
     siguiendo target (50%→63.83%→…), Critical Mode a 88 °C como red de
     seguridad.
4. **Workaround del bug de headers de PikaOS** (paquete
   `linux-headers-7.2.4-pikaos` incompleto) documentado en
   `docs/pikaos-headers-bug.md`: stub `acpi-call-dummy` vía equivs.

## Lo que SIGUE SIN RESOLVERSE

**No está confirmado que escribir en `0x3E` mueva físicamente los
ventiladores en la variante GK5NR0V.** El usuario reporta que al mandar
`nbfc set -f 0 -s 100` no se percibió aumento de velocidad de los fans.
Matiz importante: NBFC rampa de a un paso cada 3 s (~72 s del 50% al 100%) y
en la prueba se verificó a los 8 s con la rampa apenas en 63.83%, y se
canceló pronto (30→100→auto en sucesión), por lo que la prueba fue
**inconclusa, no negativa**.

Escenarios abiertos:

- **A. La config funciona y la prueba se cortó antes de tiempo.** → resolver
  con el test sostenido (abajo).
- **B. El registro `0x3E` cambia el byte pero el EC de la variante -V no
  actúa sobre él** (read compatible, write inefectivo). → hay que localizar
  el/los registros de duty reales de esta variante.
- **C. Se necesita conmutar un modo manual/automático antes de que los
  writes de duty tengan efecto** (el flag `0x4B` 01/02 es sospechoso;
  comportamiento habitual en ECs de Tongfang).

Además, la config MECHREVO define **un solo fan**; este chasis tiene dos
(CPU/GPU). Un control fino requiere una config dual.

## Próximos pasos accionables

1. **Test sostenido** (define entre A y B/C):
   ```bash
   sudo ./scripts/ec-watch.sh          # terminal 1: vigilar 0x3E y RPM
   sudo nbfc set -f 0 -s 100           # terminal 2
   # esperar 2 minutos completos; registrar: 0x3E sube a ~78 (0x4E)?
   # RPM (0x65 / 0x68-69) suben? ¿ruido audible? ¿temp se mantiene?
   sudo nbfc set -a                    # volver a automático
   ```
2. Si B/C: experimentación controlada de writes en candidatos (`0x64`,
   `0x6C`, `0x4B`) con valores dentro de rangos ya observados, documentando
   cada intento, o buscar registros documentados por la comunidad TongFang
   (r/EVOOGaming, plataforma compartida con Maingear Vector 15).
3. Redactar config NBFC propia para `EVOO EG-LP7` (dual fan) y contribuir al
   repo de configs de nbfc-linux.
4. Reportar el bug de headers de PikaOS upstream (ver
   `docs/pikaos-headers-bug.md`).
5. Correlacionar `0x4C` con `k10temp` y `0x49` con `nvidia-smi` para validar
   el mapa térmico.

## Riesgos y salvaguardas

- Escribir registros EC desconocidos puede afectar teclado/batería/gestión
  térmica. Regla del proyecto: solo escribir valores dentro de rangos ya
  observados del firmware, un registro a la vez, con dump previo y posterior.
- NBFC mantiene Critical Mode (100% forzado a 88 °C) incluso en control
  manual: red de seguridad térmica activa.
