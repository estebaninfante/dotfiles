import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // 3x3 numpad layout: top 789, middle 456, bottom 123.
  readonly property var gridOrder: [7, 8, 9, 4, 5, 6, 1, 2, 3]
  readonly property int cellSpacing: Math.max(1, Math.round(root.barSize * 0.05))
  readonly property int cellMargin: Math.max(4, Math.round(root.barSize * 0.22))
  readonly property int cellSize: Math.max(3, Math.floor((root.barSize - cellMargin * 2 - cellSpacing * 2) / 3))
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: cellSize * 3 + cellSpacing * 2 + trailingGap
  implicitHeight: root.barSize

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function stateColor(id) {
    var workspace = root.workspaceById(id)
    var occupied = workspace !== null && workspace.toplevels.values.length > 0
    var focused = Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === id

    if (focused) return Color.bar.active
    if (occupied) return Util.alpha(Color.bar.text, 0.72)
    return Util.alpha(Color.bar.text, 0.22)
  }

  Grid {
    id: grid
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    columns: 3
    rowSpacing: root.cellSpacing
    columnSpacing: root.cellSpacing

    Repeater {
      model: root.gridOrder

      Rectangle {
        required property int modelData

        width: root.cellSize
        height: root.cellSize
        radius: Math.max(1, Math.round(root.cellSize * 0.28))
        color: root.stateColor(modelData)

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(modelData)
        }
      }
    }
  }
}