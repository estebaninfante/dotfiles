# AGENTS.md — Quickshell (bar + menús de Hyprland)

Config del quickshell (barra de estado + menús) de Hyprland.

## Puntos clave

- **Este repositorio es la fuente de verdad.** `~/.config/quickshell/` es un
  symlink a `linux/config/quickshell/`. Editar SIEMPRE aquí.
- **NO se necesita rebuild ni symlinks nuevos**: la carpeta entera ya está
  enlazada. Para aplicar cambios basta **reiniciar quickshell**:
  `pkill quickshell; QT_SCALE_FACTOR=1 quickshell --no-duplicate &`
- **Regla de oro de tamaño: ningún archivo .qml supera ~300 líneas.**
  Si un componente crece, se extrae un subcomponente o servicio.

## Arquitectura (cómo navegar este código)

```
quickshell/
├── shell.qml              # ENTRY POINT. Casi sin lógica: instancia bar, menús y overlay.
├── AGENTS.md              # este archivo
├── config/                # singletons (pragma Singleton)
│   ├── Theme.qml          #   tokens de color, tipografía, tamaños de pixel
│   ├── Motion.qml         #   duraciones + easing (Behavior/Transition)
│   ├── BarConfig.qml      #   dimensiones de la barra y pills
│   └── UIState.qml        #   estado de apertura de menús + activeSection + hoversReset()
├── services/              # singletons: lógica de estado (Procesos + Timers)
│   ├── BatteryService.qml
│   ├── ClockService.qml
│   ├── AudioService.qml
│   ├── BrightnessService.qml
│   ├── KeyboardService.qml
│   ├── PowerProfileService.qml
│   ├── SyncService.qml
│   ├── MemoryService.qml
│   ├── TelemetryService.qml
│   ├── GpuModeService.qml
│   ├── WifiService.qml
│   ├── BluetoothService.qml
│   ├── ThemeService.qml
│   ├── NotifyService.qml
│   ├── GameModeService.qml
│   └── SuperKeyService.qml
├── components/            # widgets reutilizables
│   ├── Card.qml / Meter.qml      # tarjetas del widget menu (migrados de la raíz)
│   ├── IconButton.qml            # pill con icono, hover, wheel
│   ├── ToggleButton.qml          # pill ON/OFF
│   ├── SliderRow.qml             # slider + TextInput + rueda
│   ├── DeviceRow.qml             # fila de dispositivo de audio (sink/source)
│   ├── SectionLabel.qml          # etiqueta de sección
│   └── MenuShell.qml             # caja visual de los popups (borde, radio)
├── bar/                   # contenido de la barra (se instancia desde shell.qml)
│   ├── Bar.qml            #   rect negro 0.985 + composición de widgets
│   ├── Workspaces.qml
│   ├── Clock.qml
│   ├── RamIndicator.qml
│   ├── BatteryIndicator.qml
│   └── TrayButtons.qml
├── menus/                 # PopupWindows (hijos de root en shell.qml)
│   ├── ControlCenter.qml  PowerMenu.qml  DateMenu.qml  RamMenu.qml
│   ├── BrightnessMenu.qml VolumeMenu.qml WidgetMenu.qml
├── cards/                 # tarjetas del widget menu
│   ├── ThemeCard  RamCard  BattCard  GpuCard  CpuCard  SystemCard
│   ├── AudioCard  ScreenCard  WifiCard  WifiEnterpriseForm  WifiNetworkItem
│   ├── BluetoothCard  NotifCard  MonitorDetail
└── overlay/
    └── GameOverlay.qml    # overlay "modo juegos"
```

## ¿Dónde va mi cambio?

| Qué cambio | Dónde va |
|-----------|----------|
| Color, tipografía, duración de animación | `config/Theme.qml`, `config/Motion.qml` |
| Abrir/cerrar un menú, sección activa, monitorDetail | `config/UIState.qml` |
| Estado/procesos de batería, volumen, brillo, wifi, bluetooth, telemetría, etc. | `services/*Service.qml` (cada servicio posee sus Process + Timers) |
| Un pill/botón reutilizable | `components/` (IconButton, ToggleButton, SliderRow...) |
| Contenido de la barra | `bar/` |
| Popup nuevo | `menus/` + flag en `UIState` + instancia en `shell.qml` |
| Tarjeta del widget menu | `cards/` + sección en `WidgetMenu.qml` |
| Modo juegos | `overlay/GameOverlay.qml` + `services/GameModeService.qml` |

## Reglas obligatorias

1. **`shell.qml` NO tiene lógica.** Solo instancia. Lógica en services/components/menus.
2. **Procesos**: patrón `Process` de Quickshell + `StdioCollector` para stderr.
   Para re-disparar un proceso: `running = false; running = true` (separados por
   `;` en la misma línea, QML los evalúa juntos sin latencia).
3. **Cada servicio es dueño de sus Process y sus Timers.** Un servicio exporta
   funciones `refresh()`, `set()`, `toggle()`; las vistas solo llaman.
4. **Colores SIEMPRE desde `Theme.*`** (cero hex literales en las vistas).
   Solo `components/` y vistas pueden referenciar tokens; services no pintan.
5. **UI en español**, coherente con los menús existentes.
6. **Popups**: `PopupWindow { visible: opened; grabFocus: true; color: transparent; }`
   + `property bool opened` (bind a `UIState.xOpen`) + `onVisibleChanged: if (!visible) opened = false`.
7. **Apertura/estado hover centralizado en `UIState`** (`.anyMenuOpen`, `.hoversReset()`).
   La barra se expande con `UIState.anyMenuOpen`.
8. **Animaciones**: `Behavior` para cambios de propiedad; `Transition` solo para
   cambios de estado (nunca mezclar). Duración menús 200-300, hover 100-150.
   Easing: `OutCubic` entrar, `InCubic` salir, `InOutCubic` mover, `OutBack` expandir.
9. **Imports**: `import "../config"` (singletons Theme/Motion/UIState...),
   `import "../services"`, `import "../components"` según el nivel del archivo.
10. **No rompas el flujo de game mode ni los confirm dialog** (ver GameModeService).

## Correcciones frecuentes del usuario

Estas correcciones se repiten. NO vuelvas a cometerlas:

1. **Cero cambios visuales.** En refactors la UI debe quedar EXACTAMENTE igual:
   mismos colores, tamaños, paddings, fuentes, textos. Si el código viejo usa un
   valor literal, ese valor es la especificación — no lo "mejores".
2. **Comportamiento idéntico.** Mismas frecuencias de polling, mismos timers,
   mismos flujos (confirmaciones, hover, fades, onExited que re-disparan otros
   procesos). Copia los comandos de shell EXACTOS (awk/nmcli/wpctl) sin reescribir.
3. **Mantener ambos umbrales de icono de batería**: la barra usa 90/75/50/25 y
   la tarjeta del widget menu usa 90/60/30. Son distintos a propósito.
4. No tocar bloques `if machine == "X"` sin preguntar (machine-specific).

## Services — cuándo corren sus procesos

| Service | Proceso(s) | Cuándo corre |
|---------|-----------|--------------|
| BatteryService | (UPower) | siempre, bind a UPower.displayDevice |
| ClockService | date +%d %b, date full | cada 1000 ms |
| SuperKeyService | super-hold-monitor.sh | siempre (boot) |
| GameModeService | wheel-mode-monitor.sh | siempre (boot) |
| AudioService | volumeStatus | cada 3000 ms + al ajustar |
| BrightnessService | brightnessStatus | cada 3000 ms (solo con batería) |
| SyncService | syncStatus | cada 3000 ms |
| MemoryService | ramFree | cada 3000 ms |
| KeyboardService | kbStatus | boot + tras cambiar layout |
| PowerProfileService | powerProfileStatus | boot + tras set |
| TelemetryService | telemetryStatus, cpuThreadsStatus | cada 2500 ms SOLO con widget menu abierto en sección "monitoreo" |
| GpuModeService | gpuStatus | cada 5000 ms (solo laptop) |
| WifiService | wifiStatus + scan + connect | status cada 20000 ms |
| BluetoothService | bluetoothStatus + scan + action | status cada 20000 ms |
| ThemeService | themeStateRead | al abrir/refrescar |
| NotifyService | soundStateWrite | al escribir toggles |

## Cómo verificar un cambio

1. Reiniciar: `pkill quickshell; QT_SCALE_FACTOR=1 quickshell --no-duplicate &`
2. Mirar la terminal del proceso: cualquier error QML (import fallido, tipo
   desconocido, singleton no encontrado) sale ahí.
3. Verificación visual: `grim ~/shot.png` y revisar la barra.
4. Menús con popup no se pueden abrir desde script; pedir al usuario que los pruebe.
