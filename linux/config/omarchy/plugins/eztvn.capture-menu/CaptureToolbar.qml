import QtQuick
import QtQuick.Layouts
import qs.Commons

// Barra mínima: conmutador Capturar/Grabar + las tres zonas de la pantalla.
// Sin subtítulos ni pie de ayuda: el gesto (clic en ventana o arrastre) se
// explica solo, y el conmutador deja claro en qué modo está.
Item {
  id: root

  property var rows: []
  property int currentIndex: 0
  property string intent: "image"
  property real reveal: 0
  signal activated(int index)
  signal hovered(int index)
  signal modeToggled()

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

        width: modeRow.implicitWidth + Style.space(18)
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

      Rectangle {
        Layout.preferredWidth: Math.max(1, Style.space(1))
        Layout.preferredHeight: Style.space(18)
        color: Util.alpha(Color.menu.text, 0.15)
      }

      Repeater {
        model: root.rows

        delegate: Rectangle {
          id: button
          required property var modelData
          required property int index

          readonly property bool current: index === root.currentIndex

          width: itemRow.implicitWidth + Style.space(18)
          height: Style.space(34)
          radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
          color: current
            ? Util.alpha(Color.accent, 0.16)
            : (hover.containsMouse ? Color.menu.selectedBackground : "transparent")
          border.width: current ? Math.max(1, Style.space(1)) : 0
          border.color: Util.alpha(Color.accent, 0.45)

          Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
          }

          RowLayout {
            id: itemRow
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              text: button.modelData.icon
              color: button.current ? Color.accent : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.icon
            }

            Text {
              text: button.modelData.label
              color: button.current ? Color.accent : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: button.current
            }
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.hovered(button.index)
            onClicked: root.activated(button.index)
          }
        }
      }
    }
  }
}
