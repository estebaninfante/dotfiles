// ⚠️ ANTES DE EDITAR: leer ~/dotfiles/linux/config/quickshell/AGENTS.md
// Este archivo es solo ENTRY POINT: NO pone lógica aquí. Bar, menús y overlay
// son componentes separados (bar/, menus/, overlay/). Estado/procesos en services/.

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "config"
import "services"
import "bar"
import "menus"
import "overlay"

PanelWindow {
    id: root

    color: "transparent"
    exclusionMode: ExclusionMode.Normal

    anchors {
        top: true
        left: true
        right: true
        bottom: GameModeService.gameModeActive
    }

    readonly property bool expanded: hot.hovered || SuperKeyService.superHeld || UIState.anyMenuOpen

    implicitHeight: expanded ? BarConfig.expandedHeight : BarConfig.hotEdge
    exclusiveZone: GameModeService.gameModeActive ? 2000 : implicitHeight

    HoverHandler {
        id: hot
    }

    Bar {
        expanded: root.expanded
    }

    ControlCenter { root: root }
    PowerMenu { root: root }
    DateMenu { root: root }
    RamMenu { root: root }
    BrightnessMenu { root: root }
    VolumeMenu { root: root }
    WidgetMenu { root: root }
    Launcher {}

    GameOverlay { }
}