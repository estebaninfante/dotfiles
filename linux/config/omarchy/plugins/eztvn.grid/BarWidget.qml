import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Boton de barra que abre/cierra la grilla de escritorios (hyprexpo overview).
// Delega en expo_ui_toggle() del config de Hyprland para reusar el mismo reset
// de estado del fly-through que el atajo SUPER+Y.
BarWidget {
  id: root
  moduleName: "eztvn.grid"

  function toggleGrid() {
    if (root.bar) root.bar.run("hyprctl eval 'expo_ui_toggle()'")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf00a"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Grilla (overview)"
    onPressed: root.toggleGrid()
  }
}
