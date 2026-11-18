import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One captured clip: time, length and the transcript Whisper produced for it.
// Clicking plays the audio (the page owns the player, so only one clip sounds
// at a time).
CursorSurface {
  id: row

  property string stamp: ""
  property string seconds: ""
  property string transcript: ""
  property bool playing: false

  signal clicked()

  Layout.fillWidth: true
  hasCursor: mouse.containsMouse || row.playing
  current: row.playing
  implicitHeight: content.implicitHeight + Style.spacing.lg * 2

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.spacing.xl

    Text {
      textFormat: Text.PlainText
      text: row.playing ? String.fromCodePoint(0xF04D) : String.fromCodePoint(0xF04B)
      color: row.playing ? Commons.Color.accent : Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      horizontalAlignment: Text.AlignHCenter
      Layout.preferredWidth: Style.space(24)
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs

      Text {
        textFormat: Text.PlainText
        text: row.stamp + "   ·   " + row.seconds + " s"
        color: Util.alpha(Commons.Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      Text {
        textFormat: Text.PlainText
        text: row.transcript !== "" ? row.transcript : "(no text)"
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }

    Text {
      visible: row.playing
      textFormat: Text.PlainText
      text: "Playing"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
