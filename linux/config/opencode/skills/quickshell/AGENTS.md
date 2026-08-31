# Quickshell AGENTS.md — Contexto para IA

## Fuente de verdad

**Este archivo es un puntero.** La documentación viva y completa está en:

> **`~/dotfiles/linux/config/quickshell/AGENTS.md`**

Leerlo ANTES de tocar cualquier `.qml` de quickshell. Contiene: arquitectura
(repo modular, `<300` líneas por archivo), dónde va cada cambio (config/services/
components/bar/menus/cards/overlay), reglas obligatorias (patrón `Process` +
`StdioCollector`, timers por servicio, colores desde `Theme.*`, popup pattern,
`UIState` centralizado), las **correcciones frecuentes del usuario** (cero
cambios visuales, comportamiento idéntico, batería dos umbrales 90/75/50/25 bar
y 90/60/30 card), tabla de polling por servicio, y cómo verificar cambios.

## Estado actual

`shell.qml` es un **entry point sin lógica** (~40 líneas): instancia `Bar`,
los 7 menús y `GameOverlay`. Todo el resto vive en subdirectorios:
`config/` (4 singletons: Theme, Motion, BarConfig, UIState),
`services/` (14 singletons de estado), `components/` (Card, Meter, IconButton,
SliderRow, DeviceRow, SectionLabel, MenuShell), `bar/`, `menus/`, `cards/`
(WifiCard y BluetoothCard autocontenidas con sus Process), `overlay/`.

## Game Mode / estado

Estados: `gameModeActive` → `gameShown` → (usuario elige) → `gameLaunching` →
`gameArmed`. Backend `game-mode.sh` (Cartridges+Steam). Overlay en
`overlay/GameOverlay.qml`, lógica en `services/GameModeService.qml`.

## Paleta REAL (NO Catppuccin)

El sistema es **negro/blanco/gris cálido**, diseñado para miopía+astigmatismo
(sin blanco/negro puros). Tokens en `config/Theme.qml`:

```
Fondo panel/card/input: #000000      Texto principal:  #ffffff
Fondo item:            #141414       Texto secundario: #aaaaaa
Fondo item hover:      #1d1d26       Texto tenue:      #555555
Fondo hover soft:      #222222       Texto faint:      #888888
Borde:                 #333333       Acento/peligro:   #eba0ac
Texto sobre blanco:    #000000
Tipografía: JetBrainsMono Nerd Font
```

**CERO colores Catppuccin en el código real.** Si una vista muestra un hex,
ese hex es la especificación — no reemplazarlo por tokens "bonitos".

## Verificar

1. Reiniciar: `pkill quickshell; QT_SCALE_FACTOR=1 quickshell --no-duplicate &`
2. Errores QML salen en la terminal del proceso.
3. `grim ~/shot.png` para la barra; menús popup los prueba el usuario.