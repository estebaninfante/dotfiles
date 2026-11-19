import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Indicador del Agent Seat: aparece solo cuando un agente tiene ventanas abiertas
// en el asiento, con la cantidad. Clic izquierdo: salta a la ventana más nueva.
// El estado lo lee seat.sh (agent-seat status/windows), sin tocar la sesión.
BarWidget {
  id: root
  moduleName: "eztvn.seat"

  readonly property int refreshMs: Math.max(500, Number(cfg("refreshIntervalMs", 2000)))
  readonly property string scriptPath: Qt.resolvedUrl("seat.sh").toString().replace("file://", "")

  property bool running: false
  property int windows: 0
  property string titles: ""

  function cfg(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  function refresh() {
    if (!probe.running) probe.running = true
  }

  function apply(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text).trim()) } catch (e) { parsed = null }
    if (!parsed) return
    root.running = parsed.running === true
    root.windows = Number(parsed.windows) || 0
    root.titles = String(parsed.titles || "")
  }

  // Sin ventanas no ocupa lugar: el aviso es que aparece y late con el número.
  visible: root.running
  implicitWidth: root.running ? button.implicitWidth : 0
  implicitHeight: root.running ? button.implicitHeight : 0

  readonly property string barText: root.windows > 1 ? "󰖟 " + root.windows : "󰖟"
  readonly property string tooltipText: "Agent Seat · " + root.windows + " ventana(s)" +
    (root.titles.length > 0 ? " · " + root.titles : "") +
    " · clic: saltar (Super+Ctrl+Alt+X)"

  onBarChanged: root.refresh()
  Component.onCompleted: root.refresh()

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: probe
    command: [root.scriptPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipText
    onPressed: function(b) {
      if (b === Qt.LeftButton && root.bar) root.bar.run("agent-seat show")
    }
  }
}
