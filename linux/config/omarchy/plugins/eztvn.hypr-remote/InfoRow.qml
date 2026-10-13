import QtQuick
import qs.Commons

Row {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(8)

  Text {
    width: Style.space(120)
    text: root.label
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  Text {
    width: Math.max(0, root.width - Style.space(120) - root.spacing)
    wrapMode: Text.WordWrap
    text: root.value
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
