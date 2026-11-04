import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui

// Un solo ✕: cierra la ventana activa.
// Minimalista a propósito — sin título, sin estado, sin menú: un toque y listo.
// Existe para poder cerrar ventanas desde el celular (Moonlight), donde no hay
// SUPER+Q ni clic derecho.
BarWidget {
  id: root
  moduleName: "eztvn.close-window"

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string windowTitle: root.toplevel ? (root.toplevel.title || "") : ""

  visible: root.toplevel !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "✕"
    tooltipText: root.windowTitle !== "" ? "Cerrar " + root.windowTitle : "Cerrar ventana"
    onPressed: function(b) {
      if (b !== Qt.LeftButton || !root.toplevel) return
      root.toplevel.close()
    }
  }
}
