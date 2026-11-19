import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Botón del Agent Seat: un clic alterna entre el asiento y la ventana donde
// estabas (agent-seat-switch). Sólo aparece cuando el asiento tiene ventanas.
BarWidget {
  id: root
  moduleName: "eztvn.seat-switch"

  readonly property int refreshMs: Math.max(500, Number(cfg("refreshIntervalMs", 2000)))
  readonly property string scriptPath: Qt.resolvedUrl("../eztvn.seat/seat.sh").toString().replace("file://", "")

  property bool running: false
  property int windows: 0
  property string where: "user"

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
    root.where = String(parsed.where || "user")
  }

  visible: root.running
  implicitWidth: root.running ? button.implicitWidth : 0
  implicitHeight: root.running ? button.implicitHeight : 0

  readonly property bool enAsiento: root.where === "seat"
  readonly property string barText: root.enAsiento ? "󰌍" : "󰖟"
  readonly property string tooltipText: root.enAsiento
    ? "Volver a tu ventana (" + root.windows + " en el asiento)"
    : "Ir al asiento (" + root.windows + " ventana)" +
      (root.windows > 1 ? "s" : "")

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
      if (b === Qt.LeftButton && root.bar) root.bar.run("agent-seat-switch")
    }
  }
}
