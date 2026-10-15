import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../io.github.dragosol.better-displays-pro/TopologyModel.js" as Topology

Column {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property bool busy: false
  property bool failed: false
  property string status: ""
  property string detail: ""
  property var pendingPlan: null
  property string transactionId: ""

  readonly property string applyScript: String(
    Qt.resolvedUrl("../io.github.dragosol.better-displays-pro/apply-layout.sh")
  ).substring(7)

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  PanelSectionHeader {
    text: "Pantallas"
  }

  Button {
    width: parent.width
    text: root.busy ? "Sincronizando\u2026" : "Sincronizar disposición local"
    hasCursor: true
    enabled: !root.busy
    onClicked: root.start()
  }

  Text {
    width: parent.width
    visible: root.status !== ""
    textFormat: Text.PlainText
    text: root.status
    color: root.failed ? Color.urgent : Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  function noteDetail(raw) {
    var message = String(raw || "").trim()
    if (message === "") return
    var lines = message.split("\n")
    detail = lines[lines.length - 1]
  }

  function fail(message) {
    busy = false
    failed = true
    pendingPlan = null
    status = message
  }

  function start() {
    if (busy) return
    failed = false
    detail = ""
    status = "Leyendo monitores\u2026"
    monitorsProc.running = false
    monitorsProc.running = true
  }

  function applyPlan(raw) {
    var plan = Model.planLocalExtend(Model.parseMonitors(raw), Topology)
    if (!plan.valid) {
      fail(plan.reason !== "" ? plan.reason : "No se pudo preparar la disposición local")
      return
    }
    if (!plan.changed) {
      status = "La disposición local ya está alineada"
      return
    }
    pendingPlan = plan
    transactionId = "lanmouse-" + Date.now()
    busy = true
    detail = ""
    status = "Aplicando disposición\u2026"
    previewProc.command = [
      "bash", applyScript, "preview", transactionId,
      JSON.stringify(plan.proposed), JSON.stringify(plan.previous),
      "{}", "layout", plan.anchor, "", plan.originScreen, String(plan.originWorkspace)
    ]
    previewProc.running = false
    previewProc.running = true
  }

  function keepTransaction() {
    keepProc.command = ["bash", applyScript, "keep", transactionId]
    keepProc.running = false
    keepProc.running = true
  }

  function revertTransaction() {
    revertProc.command = ["bash", applyScript, "revert", transactionId]
    revertProc.running = false
    revertProc.running = true
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPlan(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.noteDetail(text)
    }
  }

  Process {
    id: previewProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.noteDetail(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.keepTransaction()
        return
      }
      root.fail(root.detail !== ""
        ? root.detail
        : "Better Displays rechazó la vista previa de la disposición")
    }
  }

  Process {
    id: keepProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.noteDetail(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.busy = false
        root.failed = false
        root.pendingPlan = null
        root.status = "Disposición local sincronizada"
        root.detail = ""
        return
      }
      root.revertTransaction()
      root.fail(root.detail !== ""
        ? root.detail
        : "No se pudo confirmar la disposición")
    }
  }

  Process {
    id: revertProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }
}
