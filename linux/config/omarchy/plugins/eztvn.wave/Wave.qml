import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Audio spectrum wave. Spawns cava with a raw ASCII output and turns each
// frame ("v1;v2;...;vN;") into a row of bars that move with the sound.
BarWidget {
  id: root
  moduleName: "eztvn.wave"

  readonly property int barCount: Math.max(6, Math.min(32, Number(setting("bars", 14)) || 14))
  readonly property int barWidth: 2
  readonly property int barGap: 1
  readonly property real maxBarHeight: Math.max(8, Math.round(root.barSize * 0.62))

  // Current frame, one value per band (0..100). Fixed length so the Repeater
  // is built once and only the bar heights animate.
  property var levels: []

  readonly property string cavaConf: Qt.resolvedUrl("cava.conf").toString().replace("file://", "")

  function handleLine(line) {
    var parts = String(line).split(";")
    var out = []
    for (var i = 0; i < parts.length && out.length < root.barCount; i++) {
      var v = parseInt(parts[i], 10)
      if (!isNaN(v)) out.push(Math.max(0, Math.min(100, v)))
    }
    if (out.length > 0) {
      root._lines++
      root.levels = out
    }
  }

  // cava streams frames continuously (zeros while silent), so a stalled line
  // count means the pipe wedged: restart the process to recover.
  property int _lines: 0
  property int _linesAtCheck: 0

  visible: true
  implicitWidth: root.barCount * root.barWidth + (root.barCount - 1) * root.barGap + 12
  implicitHeight: root.barSize

  Process {
    id: cava
    running: true
    command: ["/usr/bin/cava", "-p", root.cavaConf]
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: cava.running = true
  }

  Timer {
    id: watchdog
    interval: 4000
    running: true
    repeat: true
    onTriggered: {
      if (root._lines === root._linesAtCheck) {
        cava.running = false
        cava.running = true
      }
      root._linesAtCheck = root._lines
    }
  }

  Connections {
    target: cava
    function onExited() { restartTimer.restart() }
  }

  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: root.barGap

    Repeater {
      model: root.barCount
      Rectangle {
        width: root.barWidth
        height: Math.max(2, Math.round(((root.levels[index] || 0) / 100) * root.maxBarHeight))
        radius: root.barWidth / 2
        color: Color.accent
        anchors.verticalCenter: parent.verticalCenter

        Behavior on height { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
      }
    }
  }

  Column {
    id: col
    visible: root.vertical
    anchors.centerIn: parent
    spacing: root.barGap

    Repeater {
      model: root.barCount
      Rectangle {
        height: root.barWidth
        width: Math.max(2, Math.round(((root.levels[index] || 0) / 100) * root.maxBarHeight))
        radius: root.barWidth / 2
        color: Color.accent
        anchors.horizontalCenter: parent.horizontalCenter

        Behavior on width { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.showTooltip(root, "Audio wave")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
