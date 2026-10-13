import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "eztvn.power"
  ipcTarget: "eztvn.power"
  manageIpc: false

  property var monitor: null
  property var anchorItem: null
  property var hostWidget: null
  property bool cursorActive: false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  onOpenedChanged: if (opened) root.cursorActive = false

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          if (dx !== 0 || dy !== 0) root.cursorActive = true
          return
        }
        if (!root.monitor) return
        var delta = dx !== 0 ? dx : dy
        if (delta !== 0) root.monitor.selectProfileByDelta(delta)
      }
      onActivateRequested: if (root.cursorActive && root.monitor) root.monitor.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PowerOverview {
          monitor: root.monitor
          foreground: root.fg
          fontFamily: root.fontFamily
          opened: root.opened
        }

        PowerDetails {
          monitor: root.monitor
          foreground: root.fg
          fontFamily: root.fontFamily
          cursorActive: root.cursorActive
          onCursorActivated: root.cursorActive = true
        }
      }
    }
  }
}
