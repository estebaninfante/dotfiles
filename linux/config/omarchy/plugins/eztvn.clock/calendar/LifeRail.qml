import QtQuick
import qs.Commons
import qs.Ui

// Memento mori rail: the same meter as the year rail above it, measured against
// a nominal lifetime. Hidden until a birth year is set; double-tapping clears it.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real railWidth: Style.space(420)
  property int birthYear: 0
  property real lifeDone: 0
  property int lifeDonePercent: 0

  signal lifeCleared()

  visible: root.birthYear > 0
  width: parent ? parent.width : implicitWidth
  implicitHeight: visible ? block.height : 0

  Item {
    id: block
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.railWidth
    height: Math.max(lifeLabel.implicitHeight, Style.space(10))

    Text {
      id: lifeLabel
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "LIFE"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
    }

    Text {
      id: lifePercent
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.lifeDonePercent + "%"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    ProgressRail {
      anchors.left: lifeLabel.right
      anchors.right: lifePercent.left
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.foreground
      progress: root.lifeDone
    }

    TapHandler {
      onDoubleTapped: root.lifeCleared()
    }

    MouseArea {
      id: lifeMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.ArrowCursor

      PanelToolTip {
        visible: lifeMouse.containsMouse
        text: "Memento Mori"
        fontFamily: root.fontFamily
      }
    }
  }
}
