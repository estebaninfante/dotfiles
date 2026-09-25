import QtQuick
import qs.Commons

// Label · value caption over a slim progress rail. Shared by the system page
// (CPU, memory, disk) and the toggles page (volume, brightness) so every
// metric in the dashboard reads the same way.
Item {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string label: ""
  property string value: ""
  property real fraction: 0

  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.spacing.xs

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        font.letterSpacing: 1
      }

      Item {
        width: Math.max(0, parent.width - labelText.implicitWidth - valueText.implicitWidth - parent.spacing * 2)
        height: 1
      }

      Text {
        id: valueText
        textFormat: Text.PlainText
        text: root.value
        color: Qt.darker(root.foreground, 1.25)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(6)
      radius: Style.cornerRadius > 0 ? height / 2 : 0
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Rectangle {
        width: Math.round(parent.width * Math.max(0, Math.min(1, root.fraction)))
        height: parent.height
        radius: parent.radius
        color: root.accent

        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      }
    }
  }
}
