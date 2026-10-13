import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property int refreshMs: 2000
  property bool panelOpen: false
  property var status: null
  property bool busy: false
  property string lastError: ""

  readonly property bool apiUp: status !== null && status.running === true
  readonly property string statusScript: Qt.resolvedUrl("scripts/hypr-remote-status").toString().replace("file://", "")
  readonly property string ctlScript: Qt.resolvedUrl("scripts/hypr-remote-ctl").toString().replace("file://", "")

  signal actionFinished(string action)

  function refresh() {
    if (probe.running) return
    probe.running = true
  }

  function control(action, arg) {
    if (root.busy || !action || ctl.running) return
    root.busy = true
    root.lastError = ""
    ctl.cmd = arg ? [root.ctlScript, action, String(arg)] : [root.ctlScript, action]
    ctl.running = true
  }

  function applyStatus(text) {
    var parsed = Model.parseStatus(text)
    if (parsed) root.status = parsed
  }

  Timer {
    interval: Math.max(500, root.refreshMs)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: probe
    command: [root.statusScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(this.text)
    }
  }

  Process {
    id: ctl
    property var cmd: []
    command: cmd

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (ctl.cmd.length > 1 && String(ctl.cmd[1]) === "rotate") root.applyStatus(this.text)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var text = String(this.text).trim()
        if (text !== "") root.lastError = text
      }
    }

    onExited: function() {
      root.busy = false
      root.actionFinished(ctl.cmd.length > 1 ? String(ctl.cmd[1]) : "")
      root.refresh()
    }
  }
}
