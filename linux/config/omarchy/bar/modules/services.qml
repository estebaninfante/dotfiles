import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var bar
  property string moduleName: "services"
  property var settings

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color fg: bar ? bar.foreground : "#cdd6f4"

  property string ocState: ""
  property string sunState: ""
  property string ttsState: ""
  property string busySvc: ""

  implicitWidth: row.implicitWidth + (vertical ? 8 : 16)
  implicitHeight: bar ? bar.barSize : 26

  function colorFor(s) {
    if (s === "active") return "#9ece6a"
    if (s === "activating" || s === "reloading" || s === "deactivating") return "#e0af68"
    return "#e06c75"
  }

  function labelFor(s) {
    if (s === "active") return "activo"
    return s === "" ? "desconocido" : s
  }

  function toggle(svc) {
    if (!bar || busySvc === svc) return
    busySvc = svc
    bar.run("systemctl --user is-active --quiet " + svc + " && systemctl --user stop " + svc + " || systemctl --user start " + svc)
    settleA.restart()
  }

  function restart(svc) {
    if (!bar || busySvc === svc) return
    busySvc = svc
    bar.run("systemctl --user restart " + svc)
    settleA.restart()
  }

  Process {
    id: probe
    command: ["bash", "-lc", "systemctl --user is-active openclaw-gateway.service app-dev.lizardbyte.app.Sunshine.service voice-daemon.service 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var l = String(text).trim().split("\n")
        root.ocState = (l[0] || "").trim()
        root.sunState = (l[1] || "").trim()
        root.ttsState = (l[2] || "").trim()
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }

  Timer {
    id: settleA
    interval: 500
    onTriggered: {
      if (!probe.running) probe.running = true
      settleB.restart()
    }
  }

  Timer {
    id: settleB
    interval: 2500
    onTriggered: {
      busySvc = ""
      if (!probe.running) probe.running = true
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.vertical ? 3 : 10

    component Badge: Item {
      id: badge
      property string label
      property string svc
      property string state

      implicitWidth: content.implicitWidth
      implicitHeight: content.implicitHeight

      RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: 7
          implicitHeight: 7
          radius: 3.5
          color: root.busySvc === badge.svc ? "#e0af68" : root.colorFor(badge.state)
        }

        Text {
          Layout.alignment: Qt.AlignVCenter
          visible: !root.vertical
          text: badge.label
          color: root.fg
          font.family: bar ? bar.fontFamily : "monospace"
          font.pixelSize: 11
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(m) {
          if (m.button === Qt.RightButton) root.restart(badge.svc)
          else root.toggle(badge.svc)
        }
      }

      HoverHandler {
        onHoveredChanged: {
          if (!bar) return
          if (hovered) bar.showTooltip(badge, badge.label + ": " + root.labelFor(badge.state))
          else bar.hideTooltip(badge)
        }
      }
    }

    Badge { label: "OC"; svc: "openclaw-gateway.service"; state: root.ocState }
    Badge { label: "SUN"; svc: "app-dev.lizardbyte.app.Sunshine.service"; state: root.sunState }
    Badge { label: "TTS"; svc: "voice-daemon.service"; state: root.ttsState }
  }
}
