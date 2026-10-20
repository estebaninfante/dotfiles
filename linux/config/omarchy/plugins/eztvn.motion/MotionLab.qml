import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "motion"

// Entrada del plugin: una ventana flotante como el About de Omarchy.
// Se abre con:
//   omarchy-shell shell summon eztvn.motion '{}'
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: "eztvn.motion"
  readonly property real winW: Math.round(Style.font.body * 76)
  readonly property real winH: Math.round(Style.font.body * 50)

  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function dismiss() { close(); if (shell) shell.hide(root.pluginId) }

  FloatingWindow {
    id: window
    title: "Motion"
    visible: root.opened
    color: Commons.Color.background
    implicitWidth: root.winW
    implicitHeight: root.winH
    minimumSize: Qt.size(root.winW, root.winH)
    maximumSize: Qt.size(root.winW, root.winH)
    onVisibleChanged: if (!visible && root.opened) root.dismiss()

    Loader {
      anchors.fill: parent
      active: root.opened
      sourceComponent: Lab {
        running: root.opened
        onCloseRequested: root.dismiss()
        Component.onCompleted: reset()
      }
    }
  }
}
