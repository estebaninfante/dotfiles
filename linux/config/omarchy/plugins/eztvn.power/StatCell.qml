import QtQuick
import qs.Commons

Column {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: (parent.width - parent.spacing * 3) / 4
  spacing: Style.space(2)

  Text {
    textFormat: Text.PlainText
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.0
  }

  Text {
    textFormat: Text.PlainText
    text: root.value
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    width: parent.width
  }
}
