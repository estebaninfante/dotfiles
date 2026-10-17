import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "OsdModel.js" as OsdModel

// Notch-style OSD: a pure-black pill centered under the bar — the slot
// notifications drop into — that springs open when the volume (or brightness,
// mic, media…) changes and retracts when the timer runs out. It replaces the
// stock bordered card, which sat at the bottom of the screen.
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

  // Muted dims the fill instead of hiding it: the notch keeps showing where
  // the knob sits, but makes clear that nothing is coming out.
  readonly property bool muted: iconKey.indexOf("mute") >= 0 || (hasProgress && value <= 0)

  // Geometry. Everything is derived from `reveal` so the whole notch grows as
  // one piece: height, width and content all come out of the same spring.
  readonly property int topMargin: Style.space(30)
  readonly property int notchHeight: Style.space(46)
  readonly property int notchRadius: Style.space(23)
  readonly property int pad: Style.space(18)
  readonly property int gap: Style.space(12)
  readonly property int iconWidth: Style.space(20)
  readonly property int barWidth: Style.space(170)
  readonly property int valueWidth: Style.space(40)
  readonly property int maxMessageWidth: Style.space(280)

  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  // A plain message ("Wi-Fi conectado") has no icon of its own: drop the glyph
  // instead of borrowing the default muted speaker.
  readonly property bool showIcon: root.icon !== ""
  readonly property int contentWidth: root.hasProgress
    ? (root.showIcon ? root.iconWidth + root.gap : 0) + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : (root.showIcon ? root.iconWidth + root.gap : 0) + root.messageWidth)
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
      // Qt reads `damping` as a 0..1 ratio, not as a friction coefficient:
      // 0.58 is just shy of critical, so the notch overshoots ~8% and settles
      // in about a quarter of a second.
      spring: 20
      damping: 0.58
      mass: 1
      epsilon: 0.0005
    }
  }

  readonly property color ink: "#ffffff"
  // Pure black, not the theme's popup colour: a notch should read as a hole in
  // the screen, not as a floating card.
  readonly property color notchColor: "#000000"

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = (iconName === "" && rawValue === "") ? "" : next.icon
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
      // Sits right under the bar, in the slot notifications drop into, so the
      // clock and workspaces stay readable while the volume changes.
      anchors.top: parent.top
      anchors.topMargin: root.topMargin
      width: root.cardWidth
      height: root.cardHeight
      clip: true

      // Notch body: a black pill. Growing its height out of a zero-height box
      // anchored above makes it look like it slides down from behind the bar.
      Rectangle {
        id: card
        x: 0
        y: 0
        width: root.cardWidth
        height: root.cardHeight
        radius: Math.min(root.notchRadius, root.cardHeight / 2)
        color: root.notchColor
        // A 8% hairline keeps the pill legible over black wallpapers and black
        // notifications without turning into a visible border.
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
      }

      Row {
        anchors.centerIn: parent
        spacing: root.gap
        opacity: root.contentOpacity

        Text {
          visible: root.showIcon
          width: root.showIcon ? root.iconWidth : 0
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
                spring: 26
                damping: 0.72
                mass: 1
                epsilon: 0.3
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

