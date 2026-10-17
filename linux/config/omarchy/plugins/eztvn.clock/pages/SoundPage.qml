import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Sonido: salidas y entradas separadas de verdad.
//
// La clasificación no adivina por `isSink` ni por `node.audio` (que existe
// tanto en sinks como en sources y hacía que dispositivos de entrada
// aparecieran como salida): usa `media.class` del nodo, que PipeWire publica
// como "Audio/Sink" o "Audio/Source". Además avisa cuando la entrada elegida
// está muda o no hay ninguna, en vez de dejarte sin micrófono sin explicación.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource

  function classOf(n) {
    if (!n || !n.ready || !n.properties) return ""
    return String(n.properties["media.class"] || "")
  }
  function isDevice(n) { return !!n && !n.isStream && !!n.ready && !!n.properties }
  function isOutput(n) { return isDevice(n) && classOf(n) === "Audio/Sink" }
  function isInput(n) { return isDevice(n) && classOf(n) === "Audio/Source" }
  function collect(pred) {
    var out = []
    for (var i = 0; i < allNodes.length; i++) if (pred(allNodes[i])) out.push(allNodes[i])
    return out
  }
  readonly property var outputs: collect(isOutput)
  readonly property var inputs: collect(isInput)

  function label(n) {
    if (!n) return ""
    return String(n.nickname || n.description || n.name || "")
  }
  function detail(n) {
    if (!n) return ""
    return String(n.description || n.name || "")
  }
  function isVirtual(n) {
    if (!n || !n.properties) return false
    return !n.properties["device.id"]
  }
  function isDefaultSinkNode(n) { return !!n && !!defaultSink && n.id === defaultSink.id }
  function isDefaultSourceNode(n) { return !!n && !!defaultSource && n.id === defaultSource.id }
  function setSink(n) { if (n) Pipewire.preferredDefaultAudioSink = n }
  function setSource(n) { if (n) Pipewire.preferredDefaultAudioSource = n }

  readonly property bool inputMuted: !!defaultSource && !!defaultSource.audio && defaultSource.audio.muted
  readonly property bool noInput: !defaultSource
  readonly property bool inputWarning: noInput || inputMuted

  PwObjectTracker { objects: root.outputs }
  PwObjectTracker { objects: root.inputs }
  PwNodePeakMonitor {
    id: inputPeak
    node: root.defaultSource
    enabled: root.panelActive && !!root.defaultSource
  }

  function refresh() {}

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    // ---- Aviso de entrada ------------------------------------------------
    Rectangle {
      width: parent.width
      visible: root.inputWarning
      implicitHeight: warnText.implicitHeight + Style.space(12)
      radius: Style.space(6)
      color: Qt.rgba(1, 0.6, 0.2, 0.16)
      border.width: 1
      border.color: Qt.rgba(1, 0.6, 0.2, 0.5)

      Text {
        id: warnText
        anchors.fill: parent
        anchors.margins: Style.space(6)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        text: root.noInput
          ? "󰍭  No hay ninguna entrada seleccionada."
          : "󰍭  El micrófono está silenciado — no se te va a escuchar."
      }
    }

    // ---- Salidas ---------------------------------------------------------
    PanelSectionHeader { text: "SALIDA"; foreground: root.foreground; fontFamily: root.fontFamily }

    Repeater {
      model: root.outputs
      delegate: Rectangle {
        required property var modelData
        width: column.width
        implicitHeight: outRow.implicitHeight + Style.space(10)
        radius: Style.space(6)
        color: root.isDefaultSinkNode(modelData)
          ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"

        Row {
          id: outRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "󰓃"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            width: Math.max(0, parent.width - Style.space(140))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              text: root.label(modelData) + (root.isVirtual(modelData) ? "  ·  virtual" : "")
            }

            PanelSlider {
              width: parent.width
              minimum: 0
              maximum: 1
              step: 0.02
              value: modelData.audio ? modelData.audio.volume : 0
              onMoved: function(v) { if (modelData.audio) modelData.audio.volume = v }
            }
          }

          Button {
            text: modelData.audio && modelData.audio.muted ? "󰖁" : "󰕾"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
          }

          Button {
            text: root.isDefaultSinkNode(modelData) ? "✓" : "Usar"
            bordered: true
            enabled: !root.isDefaultSinkNode(modelData)
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.setSink(modelData)
          }
        }
      }
    }

    PanelSeparator { foreground: root.foreground }

    // ---- Entradas --------------------------------------------------------
    PanelSectionHeader { text: "ENTRADA"; foreground: root.foreground; fontFamily: root.fontFamily }

    Repeater {
      model: root.inputs
      delegate: Rectangle {
        required property var modelData
        width: column.width
        implicitHeight: inRow.implicitHeight + Style.space(10)
        radius: Style.space(6)
        color: root.isDefaultSourceNode(modelData)
          ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"

        Row {
          id: inRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "󰍬"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            width: Math.max(0, parent.width - Style.space(140))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              text: root.label(modelData)
            }

            // Barra de nivel: solo la fuente activa la mueve.
            Rectangle {
              width: parent.width
              height: Math.max(3, Style.space(4))
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.12)

              Rectangle {
                width: parent.width * (root.isDefaultSourceNode(modelData) ? Math.max(0, Math.min(1, inputPeak.peak)) : 0)
                height: parent.height
                radius: parent.radius
                color: root.foreground
              }
            }
          }

          Button {
            text: modelData.audio && modelData.audio.muted ? "󰍭" : "󰍬"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
          }

          Button {
            text: root.isDefaultSourceNode(modelData) ? "✓" : "Usar"
            bordered: true
            enabled: !root.isDefaultSourceNode(modelData)
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.setSource(modelData)
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      visible: root.inputs.length === 0
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      text: "No hay entradas de audio disponibles."
    }
  }
}
