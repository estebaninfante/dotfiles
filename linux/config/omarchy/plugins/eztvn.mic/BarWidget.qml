import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget: ganancia y nivel del micrófono en vivo.
// Un ícono de micrófono, una escalera de LEDs que sigue el nivel de entrada y
// el porcentaje de ganancia de la fuente activa. Lee una línea JSON cada ~64 ms
// del script `mic-monitor.py` (PipeWire: ganancia + nivel RMS del source default).
BarWidget {
  id: root
  moduleName: "eztvn.mic"

  property real level: 0
  property real peak: 0
  property real gain: 0
  property bool muted: false
  property string device: ""

  readonly property int segCount: 14
  readonly property real segW: 2
  readonly property real segGap: 1
  readonly property real segH: 7
  readonly property real ledW: segCount * segW + (segCount - 1) * segGap

  readonly property string scriptPath: Qt.resolvedUrl("mic-monitor.py").toString().replace("file://", "")

  readonly property string tooltip:
    "Micrófono: " + (root.device || "—") + "\n" +
    "Ganancia: " + Math.round(root.gain) + "%" + (root.muted ? " (silenciado)" : "") + "\n" +
    "Nivel: " + Math.round(root.level) + "%"

  function apply(line) {
    let d
    try { d = JSON.parse(String(line).trim()) } catch (e) { return }
    if (!d) return
    root.level = Number(d.level) || 0
    root.peak = Number(d.peak) || 0
    root.gain = Number(d.gain) || 0
    root.muted = !!d.mute
    root.device = String(d.device || "")
  }

  // Anchos fijos (texto más largo posible) para que la barra no se mueva.
  readonly property real labelW: measureGlyph.implicitWidth
  readonly property real valueW: measureValue.implicitWidth
  readonly property real hPad: Style.spaceReal(10)
  readonly property real fixedWidth: hPad * 2 + labelW + Style.space(6) + ledW + Style.space(7) + valueW

  Text {
    id: measureGlyph
    visible: false
    text: "󰍬"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    id: measureValue
    visible: false
    text: "100%"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  visible: true
  implicitWidth: root.vertical ? Style.bar.statusSlot : root.fixedWidth
  implicitHeight: root.barSize

  IpcHandler {
    target: "eztvn.mic"
    function refresh(): void { root.broadcast("refresh") }
  }

  Process {
    id: monitor
    running: true
    command: ["python3", root.scriptPath]
    stdout: SplitParser {
      onRead: function(line) { root.apply(line) }
    }
    onExited: restartTimer.restart()
  }

  // Si el monitor se cae (o parec se traba), lo relanzamos.
  Timer {
    id: restartTimer
    interval: 800
    onTriggered: monitor.running = true
  }

  // Una fila: [󰍬] [LED ladder] [ganancia].
  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: 0

    Text {
      width: root.labelW
      height: row.height
      verticalAlignment: Text.AlignVCenter
      text: root.muted ? "󰍭" : "󰍬"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: root.muted ? "#ff5a5a" : Util.alpha(Color.foreground, 0.8)
    }

    Item { width: Style.space(6); height: 1 }

    LedLadder {
      width: root.ledW
      height: root.segH
      pct: root.muted ? 0 : root.peak
      anchors.verticalCenter: parent.verticalCenter
    }

    Item { width: Style.space(7); height: 1 }

    Text {
      width: root.valueW
      height: row.height
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignRight
      text: Math.round(root.gain) + "%"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: root.muted ? "#ff5a5a"
           : root.gain <= 0 ? "#ff5a5a"
           : Util.alpha(Color.foreground, 0.82)
    }
  }

  // Vista vertical (barra lateral): ícono + ganancia.
  Column {
    id: vcol
    visible: root.vertical
    anchors.centerIn: parent
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.muted ? "󰍭" : "󰍬"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: root.muted ? "#ff5a5a" : Color.foreground
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Math.round(root.gain) + "%"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: root.muted ? "#ff5a5a" : Util.alpha(Color.foreground, 0.82)
    }
  }

  // Escalera de LEDs: verde → amarillo → rojo, con brillo en los encendidos.
  component LedLadder: Item {
    id: led
    property real pct: 0

    implicitWidth: root.ledW
    implicitHeight: root.segH

    function zoneColor(f) {
      if (f < 0.65) return "#35e04a"
      if (f < 0.88) return "#eddc2f"
      return "#ff2f2f"
    }

    function isOn(i) {
      return ((i + 0.5) / root.segCount) * 100 <= pct
    }

    Item {
      id: glowSrc
      visible: false
      layer.enabled: true
      width: led.width + 22
      height: led.height + 22
      anchors.centerIn: parent

      Row {
        anchors.centerIn: parent
        spacing: root.segGap
        Repeater {
          model: root.segCount
          Rectangle {
            width: root.segW
            height: root.segH
            radius: width / 2
            color: led.zoneColor(index / (root.segCount - 1))
            opacity: led.isOn(index) ? 1.0 : 0.14
          }
        }
      }
    }

    MultiEffect {
      anchors.fill: glowSrc
      source: glowSrc
      blurEnabled: true
      blur: 1.0
      blurMax: 16
      brightness: 0.35
      saturation: 0.15
    }

    Row {
      anchors.centerIn: parent
      spacing: root.segGap
      Repeater {
        model: root.segCount
        Rectangle {
          width: root.segW
          height: root.segH
          radius: width / 2
          color: led.zoneColor(index / (root.segCount - 1))
          opacity: led.isOn(index) ? 1.0 : 0.12
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
