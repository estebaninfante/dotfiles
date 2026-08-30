---
name: quickshell
description: Use when editing, creating, or reviewing quickshell QML files. Covers QML animations (Behavior vs Transition gotcha, Motion.qml singleton tokens, NumberAnimation, ColorAnimation, EasingCurve), modular architecture (services/, components/, config/ extraction, Process/StdioCollector patterns), UX patterns for panel/menus, and Catppuccin Mocha design system. Auto-triggers on *.qml files in quickshell config.
---

# Quickshell Skill

## Animations

Quickshell runs Qt Quick/QML. All animation primitives are Qt Quick standard.

### Behavior — animación por defecto al cambiar propiedad

Usar SIEMPRE que una propiedad cambie con interacción del usuario (hover, click, toggle).
NUNCA cambiar propiedades visuales sin Behavior.

```qml
// Hover scale en botones
Rectangle {
    width: 32; height: 32; radius: 8
    color: area.containsMouse ? "#cba6f7" : "#262633"

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    scale: area.containsMouse ? 1.05 : 1.0

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true }
}
```

### State + Transition — transiciones declarativas

Para estados complejos (abierto/cerrado, activo/inactivo). Más control que Behavior.

```qml
Rectangle {
    id: card
    property bool expanded: false

    states: [
        State {
            name: "expanded"
            when: card.expanded
            PropertyChanges { target: card; height: 200; opacity: 1 }
        },
        State {
            name: "collapsed"
            when: !card.expanded
            PropertyChanges { target: card; height: 60; opacity: 0.8 }
        }
    ]

    transitions: [
        Transition {
            from: "*"; to: "*"
            NumberAnimation { properties: "height,opacity"; duration: 250; easing.type: Easing.InOutQuad }
        }
    ]
}
```

### Tipos de animación

| Tipo | Uso | Ejemplo |
|------|-----|---------|
| `NumberAnimation` | Posición, tamaño, escala, opacidad | `Behavior on x { NumberAnimation {} }` |
| `ColorAnimation` | Colores de fondo, texto, bordes | `Behavior on color { ColorAnimation {} }` |
| `SequentialAnimation` | Pasos en orden | fade out → cambiar contenido → fade in |
| `ParallelAnimation` | Múltiples animaciones simultáneas | expand height + fade in icon |
| `RotationAnimation` | Spinners, loading indicators | — |
| `SmoothedAnimation` | Valores que cambian frecuentemente | Sliders, meters, sliders de volumen |
| `SpringAnimation` | Física de resorte (bouncy) | Sin easing predefined — usa damped harmonic oscillator |
| `PauseAnimation` | Pausa en secuencia | Delay entre elementos |
| `PropertyAction` | Cambio inmediato entre animaciones | Cambiar texto durante fade |

### Easing curves

| Curva | Sensación | Cuándo usarla |
|-------|-----------|---------------|
| `Easing.OutCubic` | Desaceleración suave (Material Design default) | **Default para enter** — la mayoría de elementos |
| `Easing.InCubic` | Aceleración suave | **Default para exit** — elementos que desaparecen |
| `Easing.InOutCubic` | Suave en ambos extremos | Transiciones de menú expand/collapse |
| `Easing.OutQuad` | Desaceleración ligera | Hover, micro-interacciones |
| `Easing.InOutQuad` | Suave ambos extremos | Transiciones de menú |
| `Easing.OutBack` | Rebote sutil | Elementos que "aparecen" (expand) |
| `Easing.OutBounce` | Rebote real | Elementos que "caen" |
| `Easing.OutElastic` | Elástico exagerado | Solo para emphasis fuerte |
| `Easing.OutSine` | Suave sinusoidal | Elementos suaves (soft) |
| `Easing.InQuad` | Aceleración | Elementos que desaparecen |

**Jerarquía de motion** (Material Design / the_quickshell_book):
- **Enter**: `OutCubic` — fast start, slow end → sensación de llegar
- **Exit**: `InCubic` — slow start, fast end → sensación de irse
- **Move**: `InOutCubic` — balanced → reubicación
- **Expand**: `OutBack` — subtle overshoot → apertura

### Motion tokens — singleton centralizado (MEJOR PRÁCTICA)

Patrón de the_quickshell_book: crear `Motion.qml` como singleton con tokens de duración y easing. Separa **qué** animas de **cómo** lo animas.

```qml
// Motion.qml
pragma Singleton
import QtQuick

QtObject {
    // Duraciones
    readonly property int durationInstant: 50
    readonly property int durationFast: 100
    readonly property int durationNormal: 200
    readonly property int durationSlow: 350
    readonly property int durationExpand: 250

    // Easings
    readonly property Easing easingEnter: Easing.OutCubic
    readonly property Easing easingExit: Easing.InCubic
    readonly property Easing easingMove: Easing.InOutCubic
    readonly property Easing easingExpand: Easing.OutBack
    readonly property Easing easingSoft: Easing.OutSine
}
```

Uso:
```qml
import "Motion.qml" as M

Behavior on opacity {
    NumberAnimation {
        duration: M.Motion.durationFast
        easing.type: M.Motion.easingEnter
    }
}
```

### ⚠️ GOTCHA: Behavior + State = roto (Qt oficial)

**Problema**: Usar `Behavior on` para animar cambios causados por `State` genera comportamiento inesperado. Al interrumpir la animación de retorno (verde→rojo) para volver al estado (verde), el base state captura el valor intermedio → el color se estanca en verde.

**Solución 1**: Usar `Transition` en vez de `Behavior` para cambios de estado:
```qml
// BIEN — Transition anima los cambios de state
states: [State { name: "on"; PropertyChanges { target: r; color: "green" } }]
transitions: Transition { ColorAnimation {} }
```

**Solución 2**: Usar binding condicional en vez de State:
```qml
// BIEN — Binding + Behavior funciona correctamente
color: area.containsMouse ? "green" : "red"
Behavior on color { ColorAnimation {} }
```

**Solución 3**: States explícitos (sin base state implícito):
```qml
states: [
    State { name: "on"; when: area.containsMouse; PropertyChanges { target: r; color: "green" } },
    State { name: "off"; when: !area.containsMouse; PropertyChanges { target: r; color: "red" } }
]
```

### Reglas de animación

1. **Duración**: 100-150ms para hover, 200-300ms para transiciones de menú, 400-600ms para page transitions
2. **SIEMPRE** usar `Behavior on` en propiedades que cambian con interacción (NO con State)
3. **Usar `Transition`** cuando la animación viene de un cambio de `State`
4. **NUNCA** usar `Timer` para animaciones visuales — eso es para polling
5. **NUNCA** animar `width`/`height` de un padre sin animar también el `clip` o el contenido
6. **Evitar** animar `layout` y `anchor` changes — ya disparan re-layouts caros. Animar `opacity`, `scale`, `x`, `y`, `color`
7. **Evitar** animaciones > 500ms en UI de panel (se siente lento)
8. **Easing**: `OutQuad`/`OutCubic` para la mayoría, `InOutCubic` para menús expand/collapse
9. **`ParallelAnimation`** para múltiples props simultáneas, **`SequentialAnimation`** para fade-out→cambiar→fade-in
10. **`reversible: true`** en Transition para que la reversa use la misma animación invertida

### Patrón de PopupWindow

```qml
PopupWindow {
    id: myMenu
    property bool opened: false
    visible: opened
    grabFocus: true
    color: "transparent"

    // Animación de apertura
    anchors { ... }
    onOpenedChanged: if (!opened) root.resetHover(sourceArea)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 14
        color: "#e60d0d12"
        border.color: "#383847"
        border.width: 1

        // Contenido del menú
    }
}
```

Para animar apertura, usar states en el popup:
```qml
PopupWindow {
    property bool opened: false
    opacity: opened ? 1 : 0
    scale: opened ? 1 : 0.94
    transformOrigin: Item.TopRight

    Behavior on opacity { NumberAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
}
```

## Arquitectura modular

### Regla cardinal: ningún archivo QML > 300 líneas

Si un archivo pasa de 300 líneas, EXTRAER componentes.

### Estructura de archivos (patrón consolidado de dotfiles reales)

Inspirado en repos exitosos: `tripathiji1312/quickshell` (132★), `mszost/quickshell-config`, `daltonkyemiller/shell`, `ekremx25/quickshell`.

```
quickshell/
├── shell.qml              # Entry point: solo carga módulos, NADA de lógica
├── config/                # Design tokens y configuración (singletons)
│   ├── Theme.qml          # Colores, fuentes, spacing
│   ├── Motion.qml         # Duration + easing tokens
│   └── BarConfig.qml      # Dimensiones de barra
├── services/              # Lógica backend, Process, state
│   ├── AudioService.qml   # PipeWire volume/mute
│   ├── BatteryService.qml # UPower state
│   ├── HyprlandService.qml# Socket2 IPC
│   └── NetworkService.qml # nmcli state
├── components/            # Reutilizables genéricos (sin lógica de negocio)
│   ├── Card.qml
│   ├── Meter.qml
│   ├── IconButton.qml
│   └── Tooltip.qml
├── menus/                 # Popups contextuales
│   ├── WidgetMenu.qml
│   ├── PowerMenu.qml
│   └── VolumeMenu.qml
├── cards/                 # Cards de sistema
│   ├── WifiCard.qml
│   ├── AudioCard.qml
│   └── BattCard.qml
└── bar/                   # Widgets de barra
    ├── Workspaces.qml
    ├── Clock.qml
    └── Indicators.qml
```

### Patrón Services (separar lógica de UI)

Los servicios son singletons QML que exponen estado. La UI los consume.

```qml
// services/AudioService.qml
pragma Singleton
import QtQuick
import Quickshell

QtObject {
    property int volume: 0
    property bool muted: false

    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = this.text.match(/Volume:\s*([\d.]+)/)
                if (match) volume = Math.round(parseFloat(match[1]) * 100)
                muted = volProc.stdout.text.includes("[MUTED]")
            }
        }
    }

    Timer { interval: 2000; running: true; repeat: true; onTriggered: volProc.running = false, volProc.running = true }

    function setVolume(v) { CommandRunner.run(["wpctl", "set-volume", "@DEFAULT_SINK@", (v/100).toFixed(2)]); volProc.running = false; volProc.running = true }
    function toggleMute() { CommandRunner.run(["wpctl", "set-mute", "@DEFAULT_SINK@", "toggle"]); volProc.running = false; volProc.running = true }
}
```

```qml
// En la UI — importar y usar directamente
import "services" as S

Text { text: S.AudioService.volume + "%" }
```

### shell.qml — entry point mínimo

shell.qml SOLO debe cargar módulos. NADA de lógica, NADA de process, NADA de state.

```qml
// shell.qml — MAL (3827 líneas de lógica)
PanelWindow {
    // 3827 líneas de TODO
}

// shell.qml — BIEN (módulos cargados)
import "services" as S
import "bar"
import "menus"
import "cards"

PanelWindow {
    id: root
    // Solo propiedades compartidas que usan todos los módulos
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property int volumePct: S.AudioService.volume
    property bool volumeMuted: S.AudioService.muted

    // Cargar componentes
    Bar {}
    WidgetMenu { id: widgetMenu }
    PowerMenu { id: powerMenu }
}
```

**Referencia**: `tripathiji1312/quickshell` — shell.qml solo importa services/, modules/, components/. `mszost/quickshell-config` — modules/ con `*Service.qml` + `*Panel.qml` + `*Widget.qml`. `daltonkyemiller/shell` — config/ con Animation.qml + Theme.qml + BarConfig.qml.

### Proceso de extracción

1. Identificar el bloque en shell.qml (tiene `id:` único)
2. Crear archivo nuevo en subcarpeta
3. Mover el bloque, manteniendo `id:` y todas sus dependencias
4. Agregar import en shell.qml: `import "menus"` o `import "cards"`
5. Usar el componente: `WifiCard { }` en shell.qml
6. Las propiedades de root se acceden via `root.propiedad` (el componente hereda el scope)

### Propiedades compartidas en root

Las propiedades que necesitan múltiples componentes van en `PanelWindow` root:
```qml
PanelWindow {
    id: root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: ...
    property double volumePct: 0
    property bool volumeMuted: false
    // etc.
}
```

### Patrón Process/StdioCollector

Cada Process que polla algo sigue este patrón:
```qml
Process {
    id: myStatus
    command: ["bash", "-c", "comando here"]
    running: true  // auto-start, o false para manual
    stdout: StdioCollector {
        onStreamFinished: {
            // Parsear this.text
            // Asignar a propiedades del componente
        }
    }
}

Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: { myStatus.running = false; myStatus.running = true }
}
```

Reglas:
- `running: true` = auto-start al cargar
- `running: false` = manual, se dispara con `proc.running = false; proc.running = true`
- **SIEMPRE** en Timer: `running = false` ANTES de `running = true` — el trigger solo funciona en transición false→true
- El Timer同期执行两个赋值 (`;` en vez de `,`) — evita race condition
- **Evitar** `CommandRunner.run()` para polling — usar Process directo

## Design tokens (Catppuccin Mocha)

### Colores

| Token | Hex | Uso |
|-------|-----|-----|
| Base | `#1e1e2e` | Fondo principal |
| Mantle | `#181825` | Fondo secundario |
| Crust | `#11111b` | Fondo más oscuro |
| Surface0 | `#313244` | Bordes, fondos de input |
| Surface1 | `#45475a` | Bordes hover |
| Overlay0 | `#6c7086` | Texto deshabilitado, placeholder |
| Overlay1 | `#7f849c` | Texto secundario |
| Subtext0 | `#a6adc8` | Labels, texto terciario |
| Text | `#cdd6f4` | Texto principal |
| Lavender | `#b4befe` | Enlaces, acento secundario |
| Mauve | `#cba6f7` | Acento primario, highlights |
| Blue | `#89b4fa` | Info, wifi, links |
| Green | `#a6e3a1` | Éxito, conectado, charged |
| Red | `#f38ba8` | Error, peligro, bajo battery |
| Yellow | `#f9e2af` | Advertencia |
| Peach | `#fab387` | Advertencia suave |
| Teal | `#94e2d5` | GPU, elementos especiales |

### Fondos de popup/card

```qml
// Fondo de popup
color: "#e60d0d12"       // 90% opacidad de #0d0d12

// Fondo de card
color: "#16161c"

// Fondo de item dentro de card
color: "#1d1d26"

// Fondo de input
color: "#0d0d12"
border.color: "#30303b"

// Hover en items
color: area.containsMouse ? "#252532" : "#1d1d26"

// Botón seleccionado/activo
color: "#29233b"
```

### Tipografía

```qml
font.family: "JetBrainsMono Nerd Font"  // SIEMPRE
font.pixelSize: 9    // Labels pequeños, badges
font.pixelSize: 10   // Texto secundario, items de lista
font.pixelSize: 11   // Texto normal en cards
font.pixelSize: 12   // Texto principal en barra
font.pixelSize: 13   // Títulos de sección
font.pixelSize: 14   // Valor grande en card
font.pixelSize: 20+  // Display (porcentaje batería, etc.)

font.bold: true      // SIEMPRE en labels de sección
font.letterSpacing: 1.5  // En labels uppercase
```

### Spacing y sizing

```qml
// Cards
radius: 14
border.width: 1
height: 84  // Card estándar

// Items de lista
height: 34  // Estándar
height: 22  // Compacto (botones de barra)

// Botones en menú
height: 34  // Acciones principales
height: 26  // Acciones secundarias

// Radius
radius: 14  // Cards, popups
radius: 8   // Items de lista, botones
radius: 6   // Badges pequeños

// Margins internos de popup
anchors.margins: 16  // Padding general
spacing: 8  // Entre elementos
```

## Errores comunes

1. **Olvidar `hoverEnabled: true`** en MouseArea — sin esto, no hay hover
2. **No poner `running: false; running: true`** para re-trigger un Process (el `;` es同步执行, no `,`)
3. **Animar `width`/`height` sin `clip: true`** — el contenido se desborda durante la animación
4. **Usar `visible: false`** en vez de `opacity: 0` — `visible` no se puede animar suavemente
5. **Usar `Behavior` para animar cambios de `State`** — Qt dice: "States and Behaviors together can cause unexpected behavior". Usar `Transition` o binding condicional
6. **Mezclar `Behavior` y `Transition`** en la misma propiedad — Transition gana, Behavior se ignora
7. **No usar `grabFocus: true`** en PopupWindow — el menú no captura teclado
8. **Olvidar `color: "transparent"`** en PopupWindow — el fondo bloquea clicks
9. **Hardcodear `font.family`** en cada Text — declarar en root y usar `root.fontFamily`
10. **No resetear hover** al cerrar menú: `onOpenedChanged: if (!opened) root.resetHover(area)`
11. **Animar `layout` o `anchor` changes** — ya disparan re-layouts caros en cada frame
12. **Poner lógica en shell.qml** — shell.qml debe ser solo entry point + propiedades compartidas
