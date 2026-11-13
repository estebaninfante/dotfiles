import QtQuick
import QtQuick.Layouts
import qs.Commons

// Barra de arriba: conmutador Capturar/Grabar y confirmar. La elección entre
// seleccionar zona o dibujar vive en la barra de abajo.
Item {
  id: root

  property string intent: "image"
  property bool canConfirm: false
  property bool showFull: false
  property real reveal: 0

  signal modeToggled()
  signal fullRequested()
  signal confirmed()

  implicitWidth: card.width
  implicitHeight: card.height

  Rectangle {
    id: card
    width: layout.implicitWidth + Style.space(16)
    height: layout.implicitHeight + Style.space(12)
    radius: Math.max(Style.space(8), Style.cornerRadius)
    color: Color.menu.background
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(Color.menu.border, 0.5)

    opacity: root.reveal
    scale: 0.97 + 0.03 * root.reveal
    transformOrigin: Item.Top

    RowLayout {
      id: layout
      anchors.centerIn: parent
      spacing: Style.space(4)

      // Conmutador del modo: el archivo sale como captura o como video.
      Rectangle {
        id: mode
        readonly property bool recording: root.intent === "video"

        // Ancho fijo: el del modo más ancho, así el botón no cambia de tamaño
        // (ni mueve el resto de la barra) al alternar Capturar/Grabar.
        readonly property real widest: Math.max(modeProbeCapture.implicitWidth,
                                                modeProbeRecord.implicitWidth)

        width: widest + Style.space(18)
        height: Style.space(34)
        radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
        color: modeArea.containsMouse
          ? Util.alpha(Color.accent, 0.24)
          : Util.alpha(Color.accent, 0.16)
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(Color.accent, 0.45)

        Behavior on color {
          ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        // Medidores invisibles: fijan el ancho al del modo que más ocupa.
        Row {
          id: modeProbeCapture
          visible: false
          spacing: Style.space(6)

          Text {
            text: "󰹑"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.icon
          }

          Text {
            text: "Capturar"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        Row {
          id: modeProbeRecord
          visible: false
          spacing: Style.space(6)

          Text {
            text: "󰻂"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.icon
          }

          Text {
            text: "Grabar"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        RowLayout {
          id: modeRow
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: mode.recording ? "󰻂" : "󰹑"
            color: mode.recording ? Color.urgent : Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.icon
          }

          Text {
            text: mode.recording ? "Grabar" : "Capturar"
            color: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        MouseArea {
          id: modeArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.modeToggled()
        }
      }

      // Captura (o graba) toda la pantalla sin elegir una zona.
      Rectangle {
        visible: root.showFull
        width: fullRow.implicitWidth + Style.space(18)
        height: Style.space(34)
        radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
        color: fullArea.containsMouse ? Color.menu.selectedBackground : "transparent"

        Behavior on color {
          ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        RowLayout {
          id: fullRow
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: "󰹞"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.icon
          }

          Text {
            text: "Pantalla"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        MouseArea {
          id: fullArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.fullRequested()
        }
      }

      // Confirmar: en área hace falta una zona; en dibujo captura la pantalla.
      Rectangle {
        visible: root.canConfirm
        width: Style.space(34)
        height: Style.space(34)
        radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
        color: confirmArea.containsMouse
          ? Util.alpha(Color.accent, 0.26)
          : Util.alpha(Color.accent, 0.16)
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(Color.accent, 0.45)

        Behavior on color {
          ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Text {
          anchors.centerIn: parent
          text: "✓"
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.icon
          font.bold: true
        }

        MouseArea {
          id: confirmArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.confirmed()
        }
      }
    }
  }
}
