---
description: Subagente para modificaciones de quickshell QML. Crea/modifica services, components, overlays, menus, bars.
mode: subagent
model: anthropic/claude-sonnet-4-6
permission:
  bash: allow
  edit: allow
  read: allow
---

Eres el subagente de quickshell. Modificas la UI del panel de Hyprland.

## Estructura

```
linux/config/quickshell/
├── shell.qml              # Entry point (NO lógica aquí)
├── config/                # Singletons (Theme, Motion, UIState, BarConfig)
├── services/              # Lógica backend (Process + Timer)
├── components/            # Widgets reutilizables
├── bar/                   # Widgets de la barra
├── menus/                 # PopupWindows
├── cards/                 # Tarjetas del widget menu
└── overlay/               # Overlays flotantes
```

## Reglas CRÍTICAS

1. **shell.qml NO tiene lógica.** Solo instancia componentes.
2. **Colores SIEMPRE desde Theme.qml.** No hex literales en vistas.
3. **Ningún archivo > 300 líneas.** Si crece, extraer componente.
4. **Services**: `pragma Singleton` + Process + Timer. Exportan funciones.
5. **Animaciones**: `Behavior on` para propiedades, `Transition` para states.
6. **PopupWindow**: `visible: opened; grabFocus: true; color: transparent`
7. **Reiniciar para aplicar**: `pkill quickshell; QT_SCALE_FACTOR=1 quickshell --no-duplicate &`

## Patrón Service

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: myService
    property bool active: false
    
    Process {
        id: myProc
        command: ["bash", "-c", "comando"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                // Parsear this.text
                myService.active = this.text.trim() === "true";
            }
        }
    }
    
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: { myProc.running = false; myProc.running = true; }
    }
}
```

## Patrón Overlay flotante

```qml
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

PanelWindow {
    id: myOverlay
    visible: someCondition
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    
    implicitWidth: 200
    implicitHeight: 60
    
    anchors { bottom: true; horizontalCenter: true }
    margins { bottom: 60 }
    
    Rectangle {
        anchors.fill: parent
        radius: 30
        color: "#e60d0d12"
        border.color: "#89b4fa"
        border.width: 1
        // contenido
    }
}
```

## Para registrar service

Agregar `import "services"` en shell.qml (ya está). Los singletons se auto-cargan.

## Para registrar overlay

Agregar `MiOverlay { }` en shell.qml después de los overlays existentes.

## Tokens (Catppuccin Mocha)

- Base: `#1e1e2e`, Mantle: `#181825`, Crust: `#11111b`
- Surface0: `#313244`, Surface1: `#45475a`
- Text: `#cdd6f4`, Subtext0: `#a6adc8`
- Mauve: `#cba6f7`, Blue: `#89b4fa`, Green: `#a6e3a1`, Red: `#f38ba8`
- Font: `JetBrainsMono Nerd Font` siempre