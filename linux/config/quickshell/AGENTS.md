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
│   ├── DashboardService.qml  # telemetría (cpu/gpu/disk) + procesos RAM
│   ├── GpuModeService.qml
│   ├── ThemeService.qml
│   ├── NotifyService.qml
│   ├── GameModeService.qml
│   ├── SuperKeyService.qml
│   ├── TasksService.qml      # centro: tareas de la nota diaria de Obsidian (tasks-ctl.sh)
│   ├── PomodoroService.qml   # centro: pomodoro + ojos (poll 1s a pomodoro.sh)
│   └── LaunchService.qml   # launcher: busca apps/archivos/scripts + IPC "launcher"
├── components/            # widgets reutilizables
│   ├── Card.qml / Meter.qml      # tarjetas del widget menu (migrados de la raíz)
│   ├── IconButton.qml            # pill con icono, hover, wheel
│   ├── SliderRow.qml             # slider + TextInput + rueda
│   ├── DeviceRow.qml             # fila de dispositivo de audio (sink/source)
│   ├── SectionLabel.qml          # etiqueta de sección
│   ├── TasksTab.qml              # pestaña TAREAS del centro (lista + añadir)
│   ├── PomodoroTab.qml           # pestaña POMODORO del centro (timer + config)
│   └── MenuShell.qml             # caja visual de los popups (borde, radio)
├── bar/                   # contenido de la barra (se instancia desde shell.qml)
│   ├── Bar.qml            #   rect negro 0.985 + composición de widgets
│   ├── Workspaces.qml
│   ├── Clock.qml
│   ├── RamIndicator.qml
│   ├── BatteryIndicator.qml
│   └── TrayButtons.qml
├── menus/                 # PopupWindows (hijos de root en shell.qml)
│   ├── ControlCenter.qml  PowerMenu.qml  RamMenu.qml
│   ├── DateMenu.qml               # centro personal: tareas (Obsidian) + pomodoro
│   ├── BrightnessMenu.qml VolumeMenu.qml WidgetMenu.qml
│   └── Launcher.qml               # busca apps/archivos/scripts (sustituyó a rofi)├── cards/                 # tarjetas del widget menu
│   ├── ThemeCard  RamCard  BattCard  GpuCard  CpuCard  SystemCard
│   ├── AudioCard  ScreenCard  WifiCard       # WifiCard autocontenida (Process propios)
│   ├── BluetoothCard  NotifCard  MonitorDetail
└── overlay/
    ├── GameOverlay.qml    # overlay "modo juegos"
    └── PomodoroPill.qml   # pill flotante del pomodoro (visible solo activo)
```

### Centro de tareas/pomodoro (DateMenu)

`menus/DateMenu.qml` (clic en el reloj) = centro personal con dos pestañas
(`UIState.dateMenuSection`: `"tareas"` | `"pomodoro"`):

- **Tareas** (`components/TasksTab.qml` + `services/TasksService.qml`): la fuente
  de verdad es la **nota diaria de Obsidian** `~/alicia/Dia/YYYY-MM-DD.md`
  (checkboxes `- [ ]`/`- [x]`). CRUD vía `~/.local/bin/tasks-ctl.sh`
  (`list|add|toggle|del|ensure`; `ensure` crea la nota desde la plantilla
  `Mental/Plantillas/nota-dia.md`). Se refresca al abrir el menú y tras cada op.
- **Pomodoro** (`components/PomodoroTab.qml` + `services/PomodoroService.qml`):
  estado y notificaciones viven en `~/.local/bin/pomodoro.sh` (archivos en
  `$XDG_RUNTIME_DIR/pomodoro/`, notify-send) → sobrevive reinicios de
  quickshell. El servicio solo hace poll (1 s) y dispara subcomandos
  (`start|pause|resume|stop|skip|config`). Config persistente en
  `~/.local/state/quickshell/pomodoro.conf` (`work_min`, `break_min`,
  `eyes_min`, `eyes_on`) editable desde la pestaña.
- **Pill flotante** (`overlay/PomodoroPill.qml`): PanelWindow propia
  (WlrLayer.Overlay, `exclusionMode: Ignore`) visible solo con el timer activo;
  clic → abre el centro en pestaña POMODORO.

### Wifi / Bluetooth: lógica dentro de las cards

A diferencia del resto, `cards/WifiCard.qml` y `cards/BluetoothCard.qml` son
**autocontenidas**: definen sus propios `Process` y el `Timer` de 20 s de
polling (`wifiStatus` / `bluetoothStatus`), con guard
`UIState.activeSection === "conexiones"`. NO hay `WifiService`/`BluetoothService`.
`WidgetMenu.refreshConnections()` solo dispara su `refreshNetworks()`/`refreshDevices()`
(leyendo `wifiCard.wifiScanning` / `bluetoothCard.btScanning` para no pisar un scan).

## ¿Dónde va mi cambio?

| Qué cambio | Dónde va |
|-----------|----------|
| Color, tipografía, duración de animación | `config/Theme.qml`, `config/Motion.qml` |
| Abrir/cerrar un menú, sección activa, monitorDetail | `config/UIState.qml` |
| Estado/procesos de batería, volumen, brillo, telemetría, etc. | `services/*Service.qml` (cada servicio posee sus Process + Timers). Wifi/bluetooth: en `cards/WifiCard.qml` / `BluetoothCard.qml` |
| Un pill/botón reutilizable | `components/` (IconButton, SliderRow...) |
| Contenido de la barra | `bar/` |
| Popup nuevo | `menus/` + flag en `UIState` + instancia en `shell.qml` |
| Launcher (busca apps/archivos/scripts) | `menus/Launcher.qml` (UI) + `services/LaunchService.qml` (datos + IPC). NO duplicar: las listas vienen de `linux/bin/apps-list.sh`, `file-list.sh`, `script-list.sh` |
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

## Launcher (sustituyó a rofi)

`services/LaunchService.qml` + `menus/Launcher.qml`. Tres modos, keybinds en
hyprland.lua (wrapper `~/.local/bin/qs-launcher.sh`):

| Modo | Keybind | Fuente | Acción Enter |
|------|---------|--------|--------------|
| `apps` | SUPER+SPACE | `apps-list.sh` (drun) | exec |
| `files` | SUPER+SHIFT+SPACE | `file-list.sh` | xdg-open / kitty-nvim (code) |
| `scripts` | SUPER+ALT+SPACE | `script-list.sh` | kitty si está en scripts/linux, si no exec |

- Abrir/cerrar por IPC: `qs ipc call launcher toggle <mode>` (válido también
  `open <mode>` / `close`). `LaunchService` expone el `IpcHandler` target
  `launcher`; no usan sockets ni DBus.
- Los producers son scripts puros (`linux/bin/*-list.sh`): emiten TSV
  `nombre<TAB>camino<TAB>...`; el contexto (Shift+Enter) y el lanzado se resuelven
  en QML (LaunchService.launch/openFile/runScript + Launcher.buildContext).
- Filtrar reasigna `LaunchService.results` (property var) para notificar a la
  lista; cap 200 resultados.
- Añadir script nuevo: los producers escanean `~/.local/bin` +
  `dotfiles/{scripts,linux,linux/bin,bin}` — sin tocar QML salvo que cambie la
  semántica de lanzado.

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
| DashboardService | telemetryStatus, cpuThreadsStatus, ramProcessesStatus | cada 2500 ms SOLO con widget menu abierto en sección "monitoreo"; procesos RAM on-demand |
| GpuModeService | gpuStatus | cada 5000 ms (solo laptop) |
| ThemeService | themeStateRead | al abrir/refrescar |
| NotifyService | soundStateWrite | al escribir toggles |
| TasksService | tasks-ctl.sh list/add/toggle/del | al abrir el centro + tras cada op |
| PomodoroService | pomodoro.sh status | cada 1000 ms (siempre) + tras cada subcomando |
| LaunchService | apps-list.sh / file-list.sh / script-list.sh | on-demand al abrir el launcher |
| WifiCard (card) | wifiStatus + scan + connect | status cada 20000 ms (guard sección "conexiones") |
| BluetoothCard (card) | bluetoothStatus + scan + action | status cada 20000 ms (guard sección "conexiones") |

## Cómo verificar un cambio

1. Reiniciar: `pkill quickshell; QT_SCALE_FACTOR=1 quickshell --no-duplicate &`
2. Mirar la terminal del proceso: cualquier error QML (import fallido, tipo
   desconocido, singleton no encontrado) sale ahí.
3. Verificación visual: `grim ~/shot.png` y revisar la barra.
4. Menús con popup no se pueden abrir desde script; pedir al usuario que los pruebe.
