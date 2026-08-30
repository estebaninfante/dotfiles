# Quickshell AGENTS.md — Contexto para IA

## Archivos

```
quickshell/
├── shell.qml        # Root PanelWindow (3827 líneas). TODO el shell vivo.
├── Card.qml         # Componente de tarjeta reutilizable (icono + título + valor + barra)
├── Meter.qml        # Barra de progreso horizontal
```

## Arquitectura actual

**Monolítica.** shell.qml contiene TODO: barra, popup menus, cards, procesos, game mode.
Plan: extraer componentes a subcarpeta.

## Propiedades root (PanelWindow)

| Propiedad | Tipo | Descripción |
|-----------|------|-------------|
| `fontFamily` | string | `"JetBrainsMono Nerd Font"` — usar SIEMPRE |
| `batt` | var | Dispositivo UPower displayDevice |
| `hasBattery` | bool | true si hay batería presente |
| `battPct` | double | Porcentaje de batería (0-100) |
| `volumePct` | double | Volumen actual (0-100) |
| `volumeMuted` | bool | true si silenciado |
| `brightnessPct` | double | Brillo (solo laptop) |
| `kbIndex` | int | 0=DV, 1=ES, 2=US |
| `powerProfile` | string | "power-saver" / "balanced" / "performance" |
| `syncActive` | bool | true si syncthing está activo |
| `superDown` / `superHeld` | bool | Estado de tecla Super |
| `gameModeActive` | bool | Modo juegos activo |
| `gameShown` / `gameClosing` / `gameLaunching` / `gameArmed` | bool | Fases del game mode |

## Procesos principales

| ID | Comando | Frecuencia | Propiedades que actualiza |
|----|---------|------------|--------------------------|
| `volumeStatus` | `wpctl get-volume` | 3s | `volumePct`, `volumeMuted` |
| `kbStatus` | `hyprctl devices -j` | Manual (al cambiar layout) | `kbIndex` |
| `audioStatus` | `wpctl status` | Al abrir menú volumen | `audioSinks`, `audioSources` |
| `brightnessStatus` | `brightnessctl -m` | 3s (solo laptop) | `brightnessPct` |
| `powerProfileStatus` | `powerprofilesctl get` | Al abrir menú energía | `powerProfile` |
| `syncStatus` | `systemctl is-active syncthing` | 3s | `syncActive` |
| `runMem` | `free -m` | 3s | ramText en barra |
| `telemetryStatus` | `/proc/stat` + `nvidia-smi` | 2.5s (menú abierto) | cpuUsage, gpuUsage, etc. |
| `ramFree` | `free -m` | 3s | ramCard.usedPct, etc. |
| `gpuStatus` | `gpu-mode.sh status` | 5s (laptop) | gpuCard.modo, fuente, acpi |

## Menús (PopupWindow)

| ID | Contenido | Ancho |
|----|-----------|-------|
| `powerMenu` | Energía: suspender, cerrar, reiniciar, apagar + perfiles | 280 |
| `volumeMenu` | Volumen + selector de dispositivos audio | 236 |
| `ramMenu` | RAM + top 10 procesos | 300 |
| `dateMenu` | Centro de tareas (placeholder) | 320 |
| `widgetMenu` | Menú principal: Conexiones, Monitoreo, Pantallas, Dispositivos, Notificaciones | 520 |
| `detailMenu` | Detalle de monitoreo (CPU/GPU/RAM/Sistema) | 560 |

## Secciones de widgetMenu

1. **conexiones** — WiFi card + Bluetooth card
2. **monitoreo** — RAM card + Battery card + GPU card + CPU card + GPU telemetry card + System card
3. **pantallas** — Screen card (configurar monitores via hyprctl)
4. **dispositivos** — Audio card (salidas, entradas, cámaras)
5. **notificaciones** — Placeholder

## Cards (en widgetMenu)

Usan componente `Card.qml` con props:
- `cIcon` — Nerd Font icon
- `cAccent` — Color del acento
- `cTitle` — Label
- `cBig` — Valor principal
- `cSub` — Texto secundario
- `cVal` — Valor numérico (0-100) para Meter
- `cardOn` — true cuando menú abierto (para animación de entrada)
- `dDel` — Delay de entrada en ms

## Game Mode

Estados: `gameModeActive` → `gameShown` → (usuario elige) → `gameLaunching` → `gameArmed`
Botones: gameBtn en barra, gameToggle(), gameEnter(), gameCancel(), gameGo(), gameExit()
Backend: `game-mode.sh` (lanza/kills Cartridges+Steam)
Overlay: pantalla fullscreen con icono pulsante y texto "CARGANDO JUEGOS..."

## Colores (Catppuccin Mocha)

```
Acento primario:  #cba6f7 (Mauve)
Acento secundario: #89b4fa (Blue)
Éxito/conectado:  #a6e3a1 (Green)
Error/peligro:    #f38ba8 (Red)
Advertencia:      #f9e2af (Yellow)
Deshabilitado:    #6c7086 (Overlay0)
Label:            #a6adc8 (Subtext0)
Texto principal:  #cdd6f4 (Text)
Fondo popup:      #e60d0d12 (90% opacidad)
Fondo card:       #16161c
Fondo item:       #1d1d26
Fondo input:      #0d0d12
Borde:            #383847
Borde input:      #30303b
Hover:            #252532
```

## Funciones root

| Función | Descripción |
|---------|-------------|
| `scanAudioDevices()` | Escanea sinks y sources de PipeWire |
| `setDefaultDevice(id)` | Cambia dispositivo audio predeterminado |
| `gameEnter()` | Entra al overlay de game mode |
| `gameCancel()` | Cancela (fade out) |
| `gameGo()` | Lanza game-mode.sh |
| `gameExit()` | Sale del modo juego |
| `resetHover(area)` | Resetea estado hover de un MouseArea |
