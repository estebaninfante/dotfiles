import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Indicador minimalista del ritmo de los agentes.
//   fluido        󰕾  habla al instante y comenta avances
//   concentración 󰈈  silencio: puntos clave al buzón, sin campana
//   campana       󰂚  campana + buzón
// Si hay mensajes pendientes, el número se suma a la etiqueta y el texto pasa
// al color de urgencia. Un clic recorre los tres modos.
BarWidget {
  id: root
  moduleName: "eztvn.modo-voz"

  readonly property int refreshMs: Math.max(500, Number(setting("refreshIntervalMs", 2000)) || 2000)
  readonly property string scriptPath: Qt.resolvedUrl("status.sh").toString().replace("file://", "")

  property string mode: "fluido"
  property int pending: 0
  property bool changing: false

  readonly property var meta: ({
    "fluido": {
      glyph: "󰕾",
      label: "fluido",
      color: Color.foreground,
      what: "los agentes hablan al instante y comentan avances"
    },
    "concentracion": {
      glyph: "󰈈",
      label: "foco",
      color: Color.muted,
      what: "silencio: solo puntos clave, los mensajes quedan en el buzón"
    },
    "campana": {
      glyph: "󰂚",
      label: "campana",
      color: Color.accent,
      what: "avisa con campana y guarda el mensaje en el buzón"
    }
  })
  readonly property var current: meta[mode] !== undefined ? meta[mode] : meta["fluido"]
  readonly property string label: current.glyph + " " + current.label + (pending > 0 ? " •" + pending : "")
  readonly property string tooltipText:
    "Modo de voz: " + (mode === "concentracion" ? "concentración (foco)" : mode) + "\n" +
    current.what +
    (pending > 0
      ? "\n" + pending + " mensaje" + (pending === 1 ? "" : "s") + " en el buzón · decí «dime»"
      : "") +
    "\nClic para cambiar: fluido → concentración → campana"

  function nextMode() {
    if (mode === "fluido") return "concentracion"
    if (mode === "concentracion") return "campana"
    return "fluido"
  }

  function apply(line) {
    var d = null
    try { d = JSON.parse(String(line).trim()) } catch (e) { return }
    if (!d) return
    if (d.mode) root.mode = String(d.mode)
    root.pending = Number(d.pending) || 0
  }

  function refresh() { if (!probe.running) probe.running = true }

  // Modo ahorro extremo (power-extreme.sh): la voz está parada; no se corre
  // `voice` cada 2 s.
  property bool paused: false
  function pause() { root.paused = true }
  function resume() { root.paused = false; root.refresh() }

  Process {
    id: extremeCheck
    running: true
    command: ["sh", "-c", "test -f \"${XDG_STATE_HOME:-$HOME/.local/state}/power-extreme/on\""]
    onExited: function(code) { if (code === 0) root.pause() }
  }

  function cycle() {
    if (changing) return
    changing = true
    changeProc.command = [scriptPath, "set", nextMode()]
    if (!changeProc.running) changeProc.running = true
  }

  implicitWidth: root.vertical ? root.barSize : button.implicitWidth
  implicitHeight: root.barSize

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.current.glyph : root.label
    foreground: root.current.color
    active: root.pending > 0
    activeColor: Color.urgent
    horizontalMargin: 8
    verticalPadding: 6
    tooltipText: root.tooltipText
    onPressed: function(b) { if (b === Qt.LeftButton) root.cycle() }
  }

  Process {
    id: probe
    command: [root.scriptPath, "status"]
    stdout: SplitParser { onRead: function(line) { root.apply(line) } }
  }

  Process {
    id: changeProc
    command: [root.scriptPath, "status"]
    stdout: SplitParser { onRead: function(line) { root.apply(line) } }
    onExited: {
      root.changing = false
      root.refresh()
    }
  }

  Timer {
    interval: root.refreshMs
    running: !root.paused
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "eztvn.modo-voz"
    function refresh(): void { root.refresh() }
    function cycle(): void { root.cycle() }
    function pause(): void { root.broadcast("pause") }
    function resume(): void { root.broadcast("resume") }
  }
}
