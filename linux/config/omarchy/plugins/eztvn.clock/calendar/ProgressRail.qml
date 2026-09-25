import QtQuick
import qs.Commons

// A slim meter used under the calendar hero for year and life progress. A
// track plus an accent fill; the fill animates so a rail that moves at
// midnight reads as motion rather than a redraw.
Item {
  id: root

  property color foreground: Color.foreground
  property real progress: 0

  implicitHeight: Style.space(6)

  Rectangle {
    id: track
    anchors.fill: parent
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

    Rectangle {
      width: Math.round(parent.width * Math.max(0, Math.min(1, root.progress)))
      height: parent.height
      radius: parent.radius
      color: Style.selectedStateColor(root.foreground, Color.accent)

      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }
}
