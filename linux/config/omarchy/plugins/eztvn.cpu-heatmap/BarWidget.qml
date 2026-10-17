import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Heatmap de CPU para la barra: una grilla de `rows` filas por tantas columnas
// como núcleos lógicos entren. Cada cuadro es un núcleo y se pinta según su
// carga instantánea con la rampa verde -> amarillo -> rojo, más un glow suave.
// Los datos salen de cpu.sh, que calcula el delta de /proc/stat por CPU.
BarWidget {
  id: root
  moduleName: "eztvn.cpu-heatmap"

  property int coreCount: 0
  // Porcentajes 0..100, uno por núcleo lógico (cpu0, cpu1, ...).
  property var cores: []

  readonly property int refreshSeconds: Math.max(1, Math.min(10, Number(setting("refreshSeconds", 1)) || 1))
  // Tope duro de 2 filas: la grilla crece a lo ancho, nunca a lo alto.
  readonly property int rows: Math.max(1, Math.min(2, Number(setting("rows", 2)) || 2))
  readonly property int columns: coreCount > 0 ? Math.ceil(coreCount / rows) : 0

  readonly property int cellSize: Math.max(3, Math.min(10, Number(setting("cellSize", 4)) || 4))
  readonly property int cellGap: 1

  readonly property real gridW: columns > 0 ? columns * cellSize + (columns - 1) * cellGap : 0
  readonly property real gridH: rows * cellSize + (rows - 1) * cellGap

  // Aire lateral: la grilla es un bloque denso, así que necesita más margen
  // que un widget de ícono para respirar al mismo ritmo que sus vecinos.
  readonly property real hPad: Style.spaceReal(10)

  readonly property real avg: {
    var list = root.cores
    if (!list || list.length === 0) return 0
    var sum = 0
    for (var i = 0; i < list.length; i++) sum += Number(list[i]) || 0
    return sum / list.length
  }

  readonly property string tooltip: root.coreCount > 0
    ? "CPU " + root.coreCount + " núcleos · media " + Math.round(root.avg) + "%"
    : "CPU calentando…"

  function zoneColor(pct) {
    if (pct < 55) return "#35e04a"
    if (pct < 80) return "#eddc2f"
    return "#ff2f2f"
  }

  function corePct(i) {
    return Number(root.cores[i]) || 0
  }

  // Los cuadros nunca se apagan del todo: un núcleo en 0% queda como una
  // brasa tenue para que la grilla siga leyéndose como tal.
  function cellOpacity(i) {
    return 0.16 + 0.84 * Math.min(1, root.corePct(i) / 100)
  }

  function apply(line) {
    var data
    try {
      data = JSON.parse(String(line).trim())
    } catch (e) {
      return
    }
    if (!data) return
    root.coreCount = Number(data.count) || 0
    root.cores = data.cores || []
  }

  function refresh() {
    if (!probe.running) probe.running = true
  }

  visible: true
  implicitWidth: root.vertical ? Style.bar.statusSlot : Math.round(root.gridW + root.hPad * 2)
  implicitHeight: root.vertical ? (root.gridH + 12) : root.barSize

  IpcHandler {
    target: "eztvn.cpu-heatmap"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Process {
    id: probe
    command: ["/bin/bash", Qt.resolvedUrl("cpu.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // La grilla en sí. Opacidad y color salen del uso de cada núcleo.
  component HeatmapCells: Grid {
    columns: root.columns
    rowSpacing: root.cellGap
    columnSpacing: root.cellGap

    Repeater {
      model: root.coreCount

      Rectangle {
        width: root.cellSize
        height: root.cellSize
        radius: Math.max(1, Math.round(root.cellSize * 0.25))
        color: root.zoneColor(root.corePct(index))
        opacity: root.cellOpacity(index)

        Behavior on color { ColorAnimation { duration: 280; easing.type: Easing.InOutQuad } }
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }
      }
    }
  }

  // Copia difusa de la grilla para el glow. Un único MultiEffect difumina la
  // grilla entera en vez de uno por cuadro.
  Item {
    id: glowSrc
    visible: false
    layer.enabled: true
    width: root.gridW + 24
    height: root.gridH + 24
    anchors.centerIn: parent

    HeatmapCells {
      anchors.centerIn: parent
    }
  }

  MultiEffect {
    anchors.fill: glowSrc
    source: glowSrc
    blurEnabled: true
    blur: 1.0
    blurMax: 16
    brightness: 0.35
    saturation: 0.2
  }

  HeatmapCells {
    anchors.centerIn: parent
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: root.refresh()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
