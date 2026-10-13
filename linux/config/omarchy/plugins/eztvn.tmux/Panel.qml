pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "eztvn.tmux"
  ipcTarget: "eztvn.tmux"
  manageIpc: false

  property var monitor: null
  property var anchorItem: null
  property var hostWidget: null
  property string pendingAction: ""
  property string pendingTarget: ""
  property string pendingSecondMessage: ""

  readonly property var sessions: monitor && monitor.sessions ? monitor.sessions : []
  readonly property int sessionCount: monitor ? monitor.count : 0
  readonly property real nowSec: monitor ? monitor.nowSec : 0
  readonly property bool loaded: monitor ? monitor.loaded : false
  readonly property bool missing: monitor ? monitor.missing : false
  readonly property bool killing: monitor ? monitor.killing : false
  readonly property int killExitCode: monitor ? monitor.killExitCode : 0
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (monitor) monitor.refresh()
  }

  function attach(name) {
    var command = Model.attachCommand(name)
    if (command.length === 0 || !bar) return
    bar.run(command)
    close()
  }

  function kill(name) {
    if (monitor) monitor.killSession(name)
  }

  function killAll() {
    if (monitor) monitor.killAllSessions()
  }

  function openConfirm(message, second, action, target) {
    if (message.length === 0) return
    root.pendingAction = action
    root.pendingTarget = target || ""
    root.pendingSecondMessage = second || ""
    confirmDialog.message = message
    confirmDialog.selectedIndex = 0
    confirmDialog.confirmText = action === "killAll" ? "Eliminar todas" : "Eliminar"
    confirmDialog.opened = true
    confirmHost.forceActiveFocus()
  }

  function requestKill(name) {
    var session = Model.sessionByName(root.sessions, name)
    if (!session) return
    root.openConfirm(
      Model.killConfirmMessage(session),
      Model.killConfirmSecond(session),
      "kill",
      String(session.name)
    )
  }

  function requestKillAll() {
    root.openConfirm(
      Model.killAllConfirmMessage(root.sessions),
      Model.killAllConfirmSecond(root.sessions),
      "killAll",
      ""
    )
  }

  function dropConfirm() {
    confirmDialog.opened = false
    root.pendingAction = ""
    root.pendingTarget = ""
    root.pendingSecondMessage = ""
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  function resolveConfirm() {
    if (root.pendingSecondMessage.length > 0) {
      confirmDialog.message = root.pendingSecondMessage
      confirmDialog.selectedIndex = 0
      root.pendingSecondMessage = ""
      return
    }
    var action = root.pendingAction
    var target = root.pendingTarget
    root.dropConfirm()
    if (action === "kill") root.kill(target)
    else if (action === "killAll") root.killAll()
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(560))

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
          spacing: Style.space(14)

          PanelHero {
            title: "tmux"
            meta: "sesiones de esta máquina"
            detail: root.loaded && root.sessionCount > 0 ? String(root.sessionCount) : ""
            foreground: root.barForeground
            fontFamily: root.fontFamily
            trailingControl: Component {
              Button {
                text: "Eliminar todas"
                visible: root.loaded && root.sessionCount > 0
                enabled: !root.killing
                bordered: true
                foreground: Color.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(10)
                implicitHeight: Math.max(32, Style.space(34))
                tooltipText: "Cerrar el server de tmux y todas sus sesiones (pide confirmación)"
                onClicked: root.requestKillAll()
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          SessionsSection {
            width: parent.width
            panel: root
          }

          PanelSeparator { foreground: root.barForeground }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            visible: root.killExitCode !== 0
            text: "No se pudo eliminar: tmux devolvió el código " + root.killExitCode + "."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Las sesiones sin adjuntar se borran solas tras 2 h de inactividad."
            color: Qt.darker(root.barForeground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "R · recargar   Esc · cerrar"
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
          cancelText: "Cancelar"

          onCanceled: root.dropConfirm()
          onConfirmed: root.resolveConfirm()
        }
      }
    }
  }
}
