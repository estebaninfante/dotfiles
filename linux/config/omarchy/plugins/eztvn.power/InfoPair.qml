import QtQuick
import qs.Commons

Row {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: parent.width
  spacing: Style.space(8)

  Text {
    textFormat: Text.PlainText
    text: root.label
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Item {
    width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
    height: 1
  }

  Text {
    textFormat: Text.PlainText
    text: root.value
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
