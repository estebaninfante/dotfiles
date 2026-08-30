---
name: quickshell
description: Use when editing, creating, or reviewing quickshell QML files. Covers QML animations (Behavior, State, Transition, NumberAnimation, ColorAnimation, EasingCurve), modular architecture (component extraction, Process patterns), UX patterns for panel/menus, and Catppuccin Mocha design system. Auto-triggers on *.qml files in quickshell config.
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

| Tipo | Uso |
|------|-----|
| `NumberAnimation` | Posición, tamaño, escala, opacidad |
| `ColorAnimation` | Colores de fondo, texto, bordes |
| `SequentialAnimation` | Pasos en orden (primero fade out, luego cambiar contenido, luego fade in) |
| `ParallelAnimation` | Múltiples animaciones simultáneas |
| `RotationAnimation` | Spinners, loading indicators |
| `SmoothedAnimation` | Valores que cambian frecuentemente (sliders, meters) |

### Easing curves

| Curva | Sensación | Cuándo usarla |
|-------|-----------|---------------|
| `Easing.OutQuad` | Desaceleración suave | Hover, micro-interacciones |
| `Easing.InOutQuad` | Suave en ambos extremos | Transiciones de menú |
| `Easing.OutBack` | Rebote sutil | Elementos que "aparecen" |
| `Easing.OutBounce` | Rebote real | Elementos que "caen" |
| `Easing.OutElastic` | Elástico exagerado | Solo para emphasis fuerte |
| `Easing.InQuad` | Aceleración | Elementos que desaparecen |

### Reglas de animación

1. **Duración**: 100-150ms para hover, 200-300ms para transiciones de menú, 400-600ms para page transitions
2. **SIEMPRE** usar `Behavior on` en propiedades que cambian con interacción
3. **NUNCA** usar `Timer` para animaciones visuales — eso es para polling
4. **NUNCA** animar `width`/`height` de un padre sin animar también el `clip` o el contenido
5. **Evitar** animaciones > 500ms en UI de panel (se siente lento)
6. **Easing**: `OutQuad` para la mayoría, `InOutQuad` para menús expand/collapse

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

### Estructura de archivos

```
quickshell/
├── shell.qml           # Root PanelWindow + propiedades compartidas + autostart
├── Card.qml            # Componente reutilizable de tarjeta
├── Meter.qml           # Barra de progreso
├── menus/
│   ├── PowerMenu.qml   # Menú de energía
│   ├── VolumeMenu.qml  # Menú de volumen
│   ├── RamMenu.qml     # Menú de RAM
│   ├── DateMenu.qml    # Centro de tareas
│   └── WidgetMenu.qml  # Menú principal del sistema
├── cards/
│   ├── WifiCard.qml    # Tarjeta de wifi
│   ├── BluetoothCard.qml
│   ├── AudioCard.qml
│   ├── ScreenCard.qml
│   ├── GpuCard.qml
│   ├── CpuCard.qml
│   └── BattCard.qml
└── bar/
    ├── Workspaces.qml  # Indicador de workspaces
    ├── Clock.qml       # Reloj
    └── Indicators.qml  # Volumen, batería, sync, teclado
```

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
    onTriggered: myStatus.running = true
}
```

Reglas:
- `running: true` = auto-start al cargar
- `running: false` = manual, se dispara con `proc.running = false; proc.running = true`
- NUNCA olvidar `running: false; running: true` para re-trigger (el trigger solo funciona en transición false→true)

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
2. **No poner `running: false; running: true`** para re-trigger un Process
3. **Animar `width`/`height` sin `clip: true`** — el contenido se desborda durante la animación
4. **Usar `visible: false`** en vez de `opacity: 0` — `visible` no se puede animar suavemente
5. **Mezclar `Behavior` y `Transition`** en la misma propiedad — Transition gana, Behavior se ignora
6. **Poner `Behavior on` en una propiedad que ya tiene `Transition`** — se cancelan
7. **No usar `grabFocus: true`** en PopupWindow — el menú no captura teclado
8. **Olvidar `color: "transparent"`** en PopupWindow — el fondo negro bloquea clicks
9. **Hardcodear `font.family`** en cada Text — declarar en root y usar `root.fontFamily`
10. **No resetear hover** al cerrar menú: `onOpenedChanged: if (!opened) root.resetHover(area)`
