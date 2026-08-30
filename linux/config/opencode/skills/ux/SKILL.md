---
name: ux
description: Use when editing UI/UX across the entire machine — quickshell panels, rofi menus, waybar, hyprland window rules, notifications, gamepad mode. Covers interaction patterns, visual consistency, sizing standards, and what NOT to do. Auto-triggers on UI-related changes to any config.
---

# Machine UX Skill

Reglas de UX para TODA la interfaz de esta máquina. Aplican a quickshell, rofi, waybar, hyprland, notificaciones, y cualquier UI que se agregue.

## Principio central

**El usuario no piensa en la interfaz.** Todo debe funcionar sin instrucciones. Si necesitas explicar cómo usar algo, está mal diseñado.

## Interacción

### Hover
- TODO MouseArea necesita `hoverEnabled: true`
- TODO elemento interactivo necesita cambio visual en hover (color, scale, opacidad)
- Hover feedback: 100-150ms, `Easing.OutQuad`
- Cursor: `Qt.PointingHandCursor` en botones/enlaces

### Click targets
- Mínimo **32×32px** para cualquier área clickeable
- Padding interno mínimo: 8px
- Si el elemento visual es más chico, el MouseArea debe ser más grande con anchors.fill en un padre con el tamaño mínimo

### Teclado
- PopupWindow SIEMPRE con `grabFocus: true`
- Navegación con Tab entre inputs
- Enter en TextInput para confirmar, Escape para cerrar menú

### Gamepad
- Los menús de quickshell se navegan con dpad + A/B
- B = cerrar (mismo patrón que Escape)
- A = seleccionar/activar
- Stick derecho = mouse virtual

## Menús

### Patrón de apertura
- Click en botón → toggle menú
- Click fuera del menú → cerrar
- Escape → cerrar
- Solo UN menú abierto a la vez (al abrir uno, cerrar otros)

### Patrón visual de menú
```qml
PopupWindow {
    color: "transparent"
    grabFocus: true
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 14
        color: "#e60d0d12"      // fondo semi-transparente
        border.color: "#383847"
        border.width: 1
    }
    // contenido con anchors.margins: 16
}
```

### Jerarquía dentro del menú
1. **Título de sección** — uppercase, bold, letterSpacing, color `#9a9aa7`, size 9-10px
2. **Elementos** — fondo `#1d1d26`, radius 8, height 34px
3. **Hover** — fondo `#252532` o `#cba6f7` (si es selección activa)
4. **Texto seleccionado** — color `#cba6f7` o `#11111b` sobre fondo mauve
5. **Separadores** — Rectangle height 1, color `#30303b`

## Consistencia visual

### Colores (Catppuccin Mocha)
Ver quickshell/AGENTS.md para la tabla completa. Regla: **mismo color = mismo significado** en toda la UI.

| Significado | Color |
|------------|-------|
| Acento/acción principal | `#cba6f7` |
| Info/conexión | `#89b4fa` |
| Éxito/conectado/cargando | `#a6e3a1` |
| Error/peligro/bajo | `#f38ba8` |
| Advertencia | `#f9e2af` |
| Deshabilitado/off | `#6c7086` |

### Tipografía
- **SIEMPRE** JetBrainsMono Nerd Font
- Labels: uppercase, bold, letterSpacing 1.5, size 9px
- Valores: size 11-14px, bold para números importantes
- Placeholder text: color `#6c7086`, size igual al input

### Spacing
- Padding de popup: 16px
- Spacing entre elementos: 8px
- Spacing entre secciones: 12px
- Radius cards/popups: 14
- Radius items/botones: 8

## Empty states

**NUNCA** mostrar "No hay datos" o "---" sin contexto.

Buenos empty states:
- WiFi sin redes: mostrar botón "Escanear" + último mensaje de estado
- Batería ausente: ocultar el elemento completamente (no mostrar "--%")
- GPU no detectada: mostrar "NO DETECTADA" con color deshabilitado
- Procesos: mostrar "Leyendo..." con spinner sutil

Malos empty states:
- "Click aquí para ver procesos" ←的手-texto innecesario
- "Sin información disponible" ← no ayuda
- Placeholder genérico que no refleja el estado real

## Reglas negativas (QUÉ NO HACER)

1. **NO** texto "Click aquí" / "Haz click" / "Clic para ver" — el hover ya indica que es clickeable
2. **NO** elementos < 32px de altura/width para áreas interactivas
3. **NO** sin hover state — todo lo clickeable debe reaccionar al hover
4. **NO** animaciones > 500ms — se siente lento
5. **NO** colores hardcoded sin seguir el palette — usar tokens
6. **NO** `visible: false` para ocultar con animación — usar `opacity: 0` + Behavior
7. **NO** texto que explique la acción — el icono + contexto deben ser suficiente
8. **NO** más de 2 niveles de profundidad en menús
9. **NO** scroll innecesario — si hay más de 8 items, considerar otro diseño
10. **NO** mensajes de error técnicos al usuario — traducir a lenguaje simple

## Notificaciones (mako/swaync)

- Timeout: 5s para info, 10s para warning, persist para error
- Icono + texto corto (máx 2 líneas)
- Colores consistentes con Catppuccin
- Posición: top-right (consistente)
- No spam: agrupar notificaciones del mismo tipo

## Hyprland window rules

- Popup menus: layer quickshell con exclusiveZone apropiado
- Floating: para menus de rofi, notificaciones
- Dim behind: para popups de quickshell (blur gaussiano)

## Rofi

- Mismo palette Catppuccin
- Keyboard navigation: type to filter, Enter para seleccionar, Escape para cerrar
- Iconos en entradas cuando sea posible
- Alt+Enter para acción secundaria (si aplica)
