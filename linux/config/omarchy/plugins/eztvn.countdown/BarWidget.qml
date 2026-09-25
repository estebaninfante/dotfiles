import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Countdown to a target date, shown as days + hours ("251d 14h").
// Target comes from shell.json (`target`, local ISO time); ticks once a
// minute via SystemClock. Width is measured against the widest string so
// the bar never shifts as the numbers change.
BarWidget {
  id: root
  moduleName: "eztvn.countdown"

  readonly property string targetRaw: String(setting("target", "2027-01-25T00:00:00"))
  readonly property var targetDate: {
    var d = new Date(targetRaw)
    return isNaN(d.getTime()) ? null : d
  }

  property date now: new Date()

  readonly property bool targetOk: targetDate !== null
  // real, not int: 122 days in ms (~1.06e10) overflows int32.
  readonly property real remainingMs: targetOk ? Math.max(0, targetDate.getTime() - now.getTime()) : 0
  readonly property int days: Math.floor(remainingMs / 86400000)
  readonly property int hours: Math.floor((remainingMs % 86400000) / 3600000)

  readonly property string label: targetOk ? days + "d " + hours + "h" : "--"
  readonly property var verticalLines: label.split(" ")
  readonly property string tooltip: targetOk
    ? "Faltan " + days + " dias " + hours + " horas\n" + targetRaw.slice(0, 10)
    : "Fecha invalida: " + targetRaw

  readonly property real labelWidth: measureLabel.implicitWidth
  readonly property real fixedWidth: labelWidth + 16

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.now = date
  }

  Text {
    id: measureLabel
    visible: false
    text: "999d 23h"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  implicitWidth: root.vertical ? Style.bar.statusSlot : root.fixedWidth
  implicitHeight: root.vertical ? (col.implicitHeight + 12) : root.barSize

  Text {
    anchors.centerIn: parent
    visible: !root.vertical
    text: root.label
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    color: root.remainingMs <= 0 ? Color.accent : Color.foreground
  }

  Column {
    id: col
    visible: root.vertical
    anchors.centerIn: parent
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.days + "d"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.foreground
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.hours + "h"
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      color: Color.foreground
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
