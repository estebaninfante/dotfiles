import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var monitor: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool opened: false

  readonly property var mon: monitor || ({})
  readonly property bool batteryPresent: root.mon.batteryPresent === true
  readonly property bool charging: root.mon.charging === true
  readonly property bool fullyCharged: root.mon.fullyCharged === true

  width: parent.width
  spacing: Style.space(14)

  Item {
    width: parent.width
    implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroRight.implicitHeight)

    Text {
      id: heroIcon
      textFormat: Text.PlainText
      text: root.batteryPresent ? String(root.mon.batteryGlyph || "") : String(root.mon.profileGlyph || "")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      Behavior on color { ColorAnimation { duration: 200 } }
    }

    Column {
      id: heroLabels
      anchors.left: heroIcon.right
      anchors.leftMargin: Style.space(14)
      anchors.right: heroRight.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        text: root.batteryPresent ? "POWER" : "POWER PROFILE"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: (root.batteryPresent ? String(root.mon.heroStatusText || "") : String(root.mon.activeProfile || "")).toUpperCase()
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        width: parent.width
      }
    }

    Column {
      id: heroRight
      visible: root.batteryPresent
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        text: String(root.mon.percentText || "—")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
        font.bold: true
        anchors.right: parent.right

        Behavior on color { ColorAnimation { duration: 200 } }
      }

      Text {
        textFormat: Text.PlainText
        text: String(root.mon.wattsText || "")
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.right: parent.right
      }
    }
  }

  Item {
    visible: root.batteryPresent
    width: parent.width
    implicitHeight: Style.space(8)

    Rectangle {
      id: barTrack
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }

    Rectangle {
      id: barFill
      anchors.left: barTrack.left
      anchors.verticalCenter: barTrack.verticalCenter
      height: barTrack.height
      radius: barTrack.radius
      color: root.foreground
      width: Math.max(barTrack.height, barTrack.width * Number(root.mon.batteryFraction || 0))

      Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

      SequentialAnimation on opacity {
        running: root.charging && !root.fullyCharged && root.opened
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 1.0; to: 0.55; duration: 480; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.55; to: 1.0; duration: 480; easing.type: Easing.InOutSine }
      }
    }
  }

  Column {
    visible: root.batteryPresent
    width: parent.width
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(windowHeader.implicitHeight, graphLegend.implicitHeight)

      Text {
        id: windowHeader
        text: "CONSUMPTION"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: graphLegend
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Row {
          spacing: Style.space(3)

          Rectangle {
            width: Style.space(6)
            height: width
            radius: width / 2
            color: Color.accent
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "DRAIN"
            color: root.foreground
            opacity: 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Row {
          spacing: Style.space(3)

          Rectangle {
            width: Style.space(6)
            height: width
            radius: width / 2
            color: graph.chargeColor
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "CHARGE"
            color: graph.chargeColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }

    ConsumptionGraph {
      id: graph
      width: parent.width
      samples: root.mon.samples || []
      minutes: Number(root.mon.graphMinutes || 10)
      revision: Number(root.mon.samplesRevision || 0)
      active: root.opened
      foreground: root.foreground
    }
  }

  Column {
    visible: root.batteryPresent
    width: parent.width
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(statsHeader.implicitHeight, scaleButtons.implicitHeight)

      Text {
        id: statsHeader
        text: "USAGE"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: scaleButtons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Repeater {
          model: root.mon.scaleOptions || []

          Button {
            required property int modelData
            text: Model.minutesLabel(modelData)
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: Number(root.mon.statsMinutes || 10) === modelData
            onClicked: if (root.monitor) root.monitor.setStatsMinutes(modelData)
          }
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(12)

      StatCell { label: "Average"; value: String(root.mon.averageText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
      StatCell { label: "Peak"; value: String(root.mon.peakText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
      StatCell { label: "Energy"; value: String(root.mon.energyText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
      StatCell { label: "Runtime"; value: String(root.mon.runtimeText || "—"); foreground: root.foreground; fontFamily: root.fontFamily }
    }
  }
}
