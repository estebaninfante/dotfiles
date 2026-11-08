import QtQuick
import QtQuick.Layouts
import qs.Commons

// Pista de la selección de región: qué va a pasar al soltar (imagen o video),
// con un conmutador para cambiar de intención sin volver a la barra.
Item {
  id: root

  property string intent: "image"
  property real reveal: 0
  signal intentPicked(string kind)

  readonly property bool video: intent === "video"

  implicitWidth: pill.width
  implicitHeight: pill.height

  Rectangle {
    id: pill
    width: content.implicitWidth + Style.space(20)
    height: content.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: Color.menu.background
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(Color.menu.border, 0.5)
    opacity: root.reveal
    scale: 0.97 + 0.03 * root.reveal

    RowLayout {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        text: root.video ? "󰻂" : "󰹑"
        color: root.video ? Color.urgent : Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        text: root.video ? "Arrastrá para grabar la zona" : "Arrastrá para capturar la zona"
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        Layout.preferredWidth: Math.max(1, Style.space(1))
        Layout.preferredHeight: Style.space(16)
        color: Util.alpha(Color.menu.text, 0.15)
      }

      Row {
        spacing: Style.space(2)

        Repeater {
          model: [
            { key: "image", label: "Imagen" },
            { key: "video", label: "Grabar" }
          ]

          delegate: Rectangle {
            id: segment
            required property var modelData
            readonly property bool current: root.intent === modelData.key

            width: segmentLabel.implicitWidth + Style.space(16)
            height: Style.space(22)
            radius: Math.max(0, Style.cornerRadius - Style.space(4))
            color: current ? Util.alpha(Color.accent, 0.18) : "transparent"
            border.width: current ? Math.max(1, Style.space(1)) : 0
            border.color: Util.alpha(Color.accent, 0.45)

            Behavior on color {
              ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            Text {
              id: segmentLabel
              anchors.centerIn: parent
              text: segment.modelData.label
              color: segment.current ? Color.accent : Util.alpha(Color.menu.text, 0.65)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              font.bold: segment.current
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.intentPicked(segment.modelData.key)
            }
          }
        }
      }

      Rectangle {
        Layout.preferredWidth: Math.max(1, Style.space(1))
        Layout.preferredHeight: Style.space(16)
        color: Util.alpha(Color.menu.text, 0.15)
      }

      Text {
        text: "Esc cancela"
        color: Util.alpha(Color.menu.text, 0.45)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
