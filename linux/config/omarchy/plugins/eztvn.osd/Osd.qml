import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "OsdModel.js" as OsdModel

// Notch-style OSD: a pure-black slab hanging from the top edge of the screen,
// centered, that springs out of the bezel when the volume (or brightness, mic,
// media…) changes and retracts as soon as the timer runs out.
Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0
  // Muted reads as an empty, dimmed bar rather than a full one: the notch
  // never lies about loudness.
  readonly property bool muted: iconKey.indexOf("mute") >= 0 || (hasProgress && value <= 0)

  // Geometry. Everything is derived from `reveal` so the whole notch grows as
  // one piece: height, width and content all come out of the same spring.
  readonly property int notchHeight: Style.space(44)
  readonly property int notchRadius: Style.space(20)
  readonly property int pad: Style.space(18)
  readonly property int gap: Style.space(12)
  readonly property int iconWidth: Style.space(20)
  readonly property int barWidth: Style.space(170)
  readonly property int valueWidth: Style.space(40)
  readonly property int maxMessageWidth: Style.space(280)

  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.gap + root.messageWidth)
  readonly property int fullWidth: root.pad * 2 + root.contentWidth

  // 0 = hidden, 1 = shown. The spring overshoots slightly, which is what gives
  // the notch its "snap out of the bezel" feel; clamp the extremes because a
  // negative height or a wildly stretched width would break the shape.
  property real reveal: 0
  readonly property real eased: Math.max(0, Math.min(1.05, reveal))
  readonly property int cardWidth: Math.round(root.fullWidth * (0.45 + 0.55 * root.eased))
  readonly property int cardHeight: Math.max(0, Math.round(root.notchHeight * root.eased))
  readonly property real contentOpacity: Math.max(0, Math.min(1, (root.eased - 0.15) / 0.8))

  Behavior on reveal {
    SpringAnimation {
      spring: 340
      damping: 32
      mass: 1
      epsilon: 0.0008
    }
  }

  readonly property color ink: "#ffffff"
  // Pure black, not the theme's popup colour: a notch should read as a hole in
  // the screen, not as a floating card.
  readonly property color notchColor: "#000000"

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    opened = true
    reveal = 1
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() {
    opened = false
    reveal = 0
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.close()
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
    text: root.message
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    // Stay mapped while the retraction spring runs, then drop the surface.
    visible: root.reveal > 0.003
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: keep the layer-shell input region empty so the OSD
    // never blocks clicks to the desktop below it.
    mask: Region {}

    Item {
      id: notch
      anchors.horizontalCenter: parent.horizontalCenter
      // Flush with the top edge: the notch comes out of the bezel.
      anchors.top: parent.top
      width: card.width
      height: card.height
      clip: true

      Shape {
        id: card
        width: root.cardWidth
        height: root.cardHeight
        preferredRendererType: Shape.CurveRenderer

        readonly property real corner: Math.min(root.notchRadius, height / 2)

        ShapePath {
          strokeWidth: 0
          fillColor: root.notchColor

          startX: 0
          startY: 0

          PathLine { x: card.width; y: 0 }
          PathLine { x: card.width; y: card.height - card.corner }
          PathArc {
            x: card.width - card.corner
            y: card.height
            radiusX: card.corner
            radiusY: card.corner
            direction: PathArc.Clockwise
          }
          PathLine { x: card.corner; y: card.height }
          PathArc {
            x: 0
            y: card.height - card.corner
            radiusX: card.corner
            radiusY: card.corner
            direction: PathArc.Clockwise
          }
          PathLine { x: 0; y: 0 }
        }
      }

      Row {
        anchors.centerIn: parent
        spacing: root.gap
        opacity: root.contentOpacity

        Text {
          width: root.iconWidth
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.icon
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
          color: root.ink
        }

        Rectangle {
          visible: root.hasProgress
          width: root.barWidth
          height: Style.space(6)
          radius: height / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(1, 1, 1, 0.16)

          Rectangle {
            height: parent.height
            radius: height / 2
            width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
            color: root.muted ? Qt.rgba(1, 1, 1, 0.35) : root.ink

            Behavior on width {
              SpringAnimation {
                spring: 520
                damping: 42
                mass: 1
                epsilon: 0.4
              }
            }
          }
        }

        Text {
          visible: root.hasProgress
          width: root.valueWidth
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.message
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Qt.rgba(1, 1, 1, 0.78)
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        Text {
          visible: !root.hasProgress && root.message !== ""
          width: root.messageWidth
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.message
          font: messageMetrics.font
          color: root.ink
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }
}

