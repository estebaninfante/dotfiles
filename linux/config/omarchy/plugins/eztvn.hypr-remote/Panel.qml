import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "eztvn.hypr-remote"
  ipcTarget: "eztvn.hypr-remote"
  manageIpc: false

  property var monitor: null
  property var anchorItem: null
  property var hostWidget: null
  property string pendingAction: ""
  property string pendingSecondMessage: ""

  readonly property var status: monitor ? monitor.status : null
  readonly property bool busy: monitor ? monitor.busy : false
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property var deviceRows: status && status.devices ? Model.deviceRows(status.devices, Date.now()) : []
  readonly property string ctlScript: Qt.resolvedUrl("scripts/hypr-remote-ctl").toString().replace("file://", "")

  function refresh() {
    if (monitor) monitor.refresh()
  }

  function control(action, arg) {
    if (monitor) monitor.control(action, arg)
  }

  function copyText(value) {
    if (!value) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  function openLogs() {
    if (!bar) return
    bar.run("xdg-terminal-exec --hold -- " + Util.shellQuote(root.ctlScript) + " logs")
  }

  function scrollBy(direction) {
    var flick = scroll.contentItem
    if (!flick || flick.contentY === undefined || direction === 0) return
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    var step = Style.space(48)
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + (direction > 0 ? step : -step)))
  }

  function resetScroll() {
    var flick = scroll.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function requestConfirm(action, message, secondMessage) {
    root.pendingAction = action
    root.pendingSecondMessage = secondMessage || ""
    confirmDialog.message = message
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
    confirmHost.forceActiveFocus()
  }

  function resolveConfirm() {
    if (root.pendingSecondMessage.length > 0) {
      confirmDialog.message = root.pendingSecondMessage
      confirmDialog.selectedIndex = 1
      root.pendingSecondMessage = ""
      return
    }
    var action = root.pendingAction
    confirmDialog.opened = false
    root.pendingAction = ""
    if (action === "rotate") root.control("rotate")
    else if (action === "unpairAll") root.control("unpair-all")
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  onOpenedChanged: if (opened) {
    root.refresh()
    Qt.callLater(function() {
      root.resetScroll()
      catcher.forceActiveFocus()
    })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      blocked: confirmDialog.opened
      onMoveRequested: function(dx, dy) { root.scrollBy(dy !== 0 ? dy : dx) }
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(12)

          StatusSection {
            width: parent.width
            panel: root
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          PairSection {
            width: parent.width
            panel: root
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          DevicesSection {
            width: parent.width
            panel: root
          }

          PanelSeparator { width: parent.width; foreground: root.barForeground }

          ServiceSection {
            width: parent.width
            panel: root
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "R · recargar estado"
            color: Qt.darker(root.barForeground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Item {
        id: confirmHost
        anchors.fill: parent
        z: 100
        focus: confirmDialog.opened

        Keys.onPressed: function(event) {
          if (confirmDialog.opened && confirmDialog.handleKey(event)) event.accepted = true
        }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          background: Color.popups.background
          foreground: root.barForeground
          scrim: Util.alpha(Color.popups.background, 0.72)
          fontFamily: root.fontFamily

          onCanceled: {
            opened = false
            root.pendingAction = ""
            root.pendingSecondMessage = ""
            Qt.callLater(function() { catcher.forceActiveFocus() })
          }
          onConfirmed: root.resolveConfirm()
        }
      }
    }
  }
}
