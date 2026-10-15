import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property bool opened: false
  property real scrimOpacity: 0
  property real reveal: 0
  property real progress: 0
  property real cursorOpacity: 1
  property int durationMs: 2600

  readonly property int fadeMs: Math.round(durationMs * 0.14)
  readonly property int progressMs: Math.max(1, durationMs - fadeMs)
  readonly property int cleanupMs: durationMs + 1600
  readonly property int blinkMs: 520
  readonly property int paneSize: Style.space(42)
  readonly property int paneGap: Style.space(12)
  readonly property int trackHeight: Style.space(6)

  function start(raw) {
    var requested = parseInt(String(raw), 10)
    durationMs = (isFinite(requested) && requested >= 1200 && requested <= 6000) ? requested : 2600
    scrimOpacity = 0
    reveal = 0
    progress = 0
    opened = true
    runAnimation.restart()
    cleanupTimer.restart()
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (error) { payload = {} }
    start(payload.durationMs)
  }

  function close() {
    cleanupTimer.stop()
    runAnimation.stop()
    opened = false
    scrimOpacity = 0
    reveal = 0
    progress = 0
  }

  SequentialAnimation {
    id: runAnimation

    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "scrimOpacity"
        from: 0
        to: 1
        duration: root.fadeMs
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: Math.round(root.fadeMs * 1.9)
        easing.type: Easing.OutCubic
      }
    }

    NumberAnimation {
      target: root
      property: "progress"
      from: 0
      to: 1
      duration: root.progressMs
      easing.type: Easing.Linear
    }
  }

  SequentialAnimation {
    running: root.opened
    loops: Animation.Infinite

    NumberAnimation { target: root; property: "cursorOpacity"; to: 1; duration: root.blinkMs }
    NumberAnimation { target: root; property: "cursorOpacity"; to: 0; duration: root.blinkMs }
  }

  Timer {
    id: cleanupTimer
    interval: root.cleanupMs
    onTriggered: root.close()
  }

  IpcHandler {
    target: "eztvn.boot-console"

    function play(durationMs: string): string {
      root.start(durationMs)
      return "ok"
    }

    function close(): string {
      root.close()
      return "ok"
    }

    function state(): string {
      return root.opened ? "playing" : "idle"
    }

    function ping(): string {
      return "ok"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData

      screen: modelData
      visible: root.opened
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-boot-console"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.scrimOpacity)
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(30)
        opacity: root.reveal

        TextMetrics {
          id: wordmarkMetrics
          font: wordmark.font
          text: wordmark.text
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "SIGUIENTE ARRANQUE"
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.letterSpacing: 6
        }

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(16)

          Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 2
            spacing: root.paneGap

            Repeater {
              model: 4

              Rectangle {
                width: root.paneSize
                height: root.paneSize
                radius: Style.space(2)
                color: Util.alpha(Color.accent, 0.92)
              }
            }
          }

          Text {
            id: wordmark

            anchors.horizontalCenter: parent.horizontalCenter
            text: "WINDOWS"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.displayLarge * 2.8)
            font.bold: true
            font.letterSpacing: 6
          }
        }

        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.ceil(wordmarkMetrics.advanceWidth)
          height: root.trackHeight

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Util.alpha(Color.foreground, 0.14)
          }

          Rectangle {
            width: parent.width * root.progress
            height: parent.height
            radius: height / 2
            color: Color.accent
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Cambiando a modo consola"
            color: Util.alpha(Color.foreground, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: Style.space(13)
            radius: Style.space(1)
            color: Util.alpha(Color.accent, 0.85 * root.cursorOpacity)
          }
        }
      }
    }
  }
}
