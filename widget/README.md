# Widget Caelestia — monitor de fans GK5NR0V

Plugin de quickshell para el escritorio Caelestia (CachyOS): tarjeta
compacta arriba a la derecha con RPMs y temperaturas en vivo.

```
┌─────────────────────────┐
│ CPU   71°        1646 rpm│
│ GPU   48°       fan-stop │
└─────────────────────────┘
```

- **RPMs** desde el módulo hwmon `gk5nr0v-fans` (véase `module/`).
- **Temp CPU** desde `k10temp`; **temp dGPU** vía `nvidia-smi` cada 5 s
  (intervalo deliberado: consultarlo despierta brevemente la dGPU).
- Color de temperatura: azul <60°, verde <72°, ámbar <82°, rojo ≥82°.
- Autosuficiente: solo importa QtQuick + Quickshell, sin internos de
  Caelestia — sobrevive a actualizaciones del shell.
- `0 rpm` se muestra como `fan-stop` (la dGPU corta el fan bajo ~55°).

## Instalación

```bash
mkdir -p ~/.config/caelestia/plugins/gk5nr0v-fans
cp widget/caelestia-plugin/{main.qml,read-sensors.sh,metadata.json} \
    ~/.config/caelestia/plugins/gk5nr0v-fans/
chmod +x ~/.config/caelestia/plugins/gk5nr0v-fans/read-sensors.sh
systemctl --user restart caelestia-shell
```

El cargador de plugins de Caelestia lo levanta al arranque del shell
(directorio oficial de plugins de usuario; gestión/toggle desde
Nexus → Plugins).

## Verificación / depuración

```bash
quickshell -p ~/.config/quickshell/caelestia/shell.qml ipc call fans readings
quickshell -p ~/.config/quickshell/caelestia/shell.qml ipc call plugins count
bash ~/.config/caelestia/plugins/gk5nr0v-fans/read-sensors.sh gpu
```

## Notas de diseño

- Lecturas hwmon cada 1 s (proceso bash que descubre los índices hwmon
  por nombre — los números `hwmonN` cambian entre arranques).
- Posición: `anchors top+right`, margen 48 px bajo la barra;
  `exclusiveZone: 0` (overlay, no reserva espacio).
- Quickshell 0.3.1: `exclusiveZone` es int; `Qt.resolvedUrl()` devuelve
  QUrl (hacer `.toString()`); no existe `primaryScreen` (usar
  `Quickshell.screens[0]`).
- El sensor script omite silenciosamente sensores ausentes (módulo sin
  cargar, dGPU dormida) — el widget degrada a `--` en vez de romperse.
