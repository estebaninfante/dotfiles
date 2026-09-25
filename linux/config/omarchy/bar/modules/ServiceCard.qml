import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: card

  required property var modelData
  property var module

  readonly property var svc: modelData
  readonly property bool busy: module ? module.busySvc === svc.svc : false
  readonly property bool isActive: svc.state === "active"
  readonly property bool starts: module ? module.isEnabled(svc.enabled) : false
  readonly property string stateLabel: module ? module.labelFor(svc.state) : ""

  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color tone: module ? (busy ? module.warnColor : module.colorFor(svc.state)) : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family

  width: parent ? parent.width : 0
  height: Style.space(84)
  radius: Style.space(Style.cornerRadius > 0 ? 10 : 0)
  color: hover.hovered || busy ? Util.alpha(fg, 0.075) : Util.alpha(fg, 0.035)
  border.width: 1
  border.color: Util.alpha(tone, busy ? 0.38 : 0.10)

  Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
  Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

  HoverHandler { id: hover }

  Rectangle {
    id: accent
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(12)
    anchors.bottomMargin: Style.space(12)
    width: Style.space(3)
    radius: width / 2
    color: card.tone
    Behavior on color { ColorAnimation { duration: 160 } }
  }

  Rectangle {
    id: iconTile
    anchors.left: accent.right
    anchors.leftMargin: Style.space(10)
    anchors.top: parent.top
    anchors.topMargin: Style.space(11)
    width: Style.space(32)
    height: width
    radius: Style.space(Style.cornerRadius > 0 ? 9 : 0)
    color: Util.alpha(card.tone, 0.14)
    border.width: 1
    border.color: Util.alpha(card.tone, 0.28)
    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on border.color { ColorAnimation { duration: 160 } }

    Text {
      anchors.centerIn: parent
      text: card.svc.glyph
      color: card.tone
      font.family: card.fontFamily
      font.pixelSize: Style.font.icon
      Behavior on color { ColorAnimation { duration: 160 } }
    }

    Rectangle {
      id: activity
      anchors.fill: parent
      radius: parent.radius
      color: "transparent"
      border.width: 1
      border.color: card.tone
      opacity: 0

      SequentialAnimation on opacity {
        running: card.busy
        loops: Animation.Infinite
        NumberAnimation { to: 0.85; duration: 500; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.15; duration: 500; easing.type: Easing.InQuad }
        onRunningChanged: if (!running) activity.opacity = 0
      }
    }
  }

  Column {
    id: identity
    anchors.left: iconTile.right
    anchors.leftMargin: Style.space(11)
    anchors.right: topActions.left
    anchors.rightMargin: Style.space(8)
    anchors.top: iconTile.top
    anchors.topMargin: Style.space(1)
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: card.svc.label
      color: card.fg
      font.family: card.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: card.svc.desc
      color: card.dim
      font.family: card.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Row {
    id: topActions
    anchors.right: parent.right
    anchors.rightMargin: Style.space(11)
    anchors.top: parent.top
    anchors.topMargin: Style.space(12)
    spacing: Style.space(6)

    StateChip {
      tone: card.tone
      text: card.stateLabel
      pulse: card.busy
    }

    IconAction {
      glyph: "󰑓"
      busy: card.busy
      onActivated: card.module.restartService(card.svc.svc)
    }
  }

  ServiceActions {
    id: controls
    anchors.left: iconTile.right
    anchors.leftMargin: Style.space(11)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(11)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(11)
    module: card.module
    svc: card.svc
    starts: card.starts
    active: card.isActive
    busy: card.busy
  }

  component StateChip: Rectangle {
    id: chip

    property color tone: card.fg
    property string text: ""
    property bool pulse: false

    implicitWidth: chipRow.implicitWidth + Style.space(14)
    height: Style.space(20)
    radius: height / 2
    color: Util.alpha(chip.tone, 0.13)
    border.width: 1
    border.color: Util.alpha(chip.tone, 0.30)
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Rectangle {
        id: chipDot
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(6)
        height: width
        radius: width / 2
        color: chip.tone
        Behavior on color { ColorAnimation { duration: 150 } }

        SequentialAnimation on opacity {
          running: chip.pulse
          loops: Animation.Infinite
          NumberAnimation { to: 0.3; duration: 450; easing.type: Easing.OutQuad }
          NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
          onRunningChanged: if (!running) chipDot.opacity = 1
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.text
        color: chip.tone
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        Behavior on color { ColorAnimation { duration: 150 } }
      }
    }
  }

  component IconAction: Rectangle {
    id: action

    property string glyph
    property bool busy: false
    signal activated

    width: Style.space(24)
    height: Style.space(24)
    radius: Style.space(Style.cornerRadius > 0 ? 7 : 0)
    color: actionMouse.containsMouse ? Util.alpha(card.fg, 0.13) : "transparent"
    border.width: 1
    border.color: actionMouse.containsMouse ? Util.alpha(card.fg, 0.26) : Util.alpha(card.fg, 0.10)
    opacity: action.busy ? 0.4 : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: action.glyph
      color: actionMouse.containsMouse ? card.fg : card.dim
      font.family: card.fontFamily
      font.pixelSize: Style.font.bodySmall
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: !action.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: action.activated()
    }
  }
}
