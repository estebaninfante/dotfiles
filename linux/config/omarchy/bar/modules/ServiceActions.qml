import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: controls

  required property var module
  required property var svc
  required property bool starts
  required property bool active
  required property bool busy

  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color ok: module ? module.okColor : Color.accent
  readonly property color down: module ? module.downColor : Color.urgent
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family

  implicitHeight: Style.space(22)

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(7)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Inicio"
      color: controls.starts ? controls.fg : controls.dim
      font.family: controls.fontFamily
      font.pixelSize: Style.font.caption
      Behavior on color { ColorAnimation { duration: 130 } }
    }

    MiniSwitch {
      on: controls.starts
      busy: controls.busy
      onToggled: controls.module.toggleStartup(controls.svc.svc, controls.svc.enabled)
    }
  }

  SessionButton {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    active: controls.active
    busy: controls.busy
    onActivated: controls.module.toggleService(controls.svc.svc, controls.svc.state)
  }

  component MiniSwitch: Item {
    id: sw

    property bool on: false
    property bool busy: false
    signal toggled

    implicitWidth: track.width
    implicitHeight: track.height
    opacity: sw.busy ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      id: track
      width: Style.space(32)
      height: Style.space(17)
      radius: height / 2
      color: sw.on ? Util.alpha(controls.ok, 0.22) : Util.alpha(controls.fg, 0.10)
      border.width: 1
      border.color: sw.on ? Util.alpha(controls.ok, 0.55) : Util.alpha(controls.fg, 0.20)
      Behavior on color { ColorAnimation { duration: 130 } }
      Behavior on border.color { ColorAnimation { duration: 130 } }

      Rectangle {
        id: knob
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(11)
        height: width
        radius: width / 2
        x: sw.on ? track.width - width - Style.space(3) : Style.space(3)
        color: sw.on ? controls.ok : Util.alpha(controls.fg, 0.7)
        Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 130 } }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !sw.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  component SessionButton: Rectangle {
    id: session

    property bool active: false
    property bool busy: false
    signal activated

    readonly property color tone: session.active ? controls.down : controls.ok
    readonly property string glyph: session.active ? "󰓛" : "󰐊"
    readonly property string label: session.active ? "Detener" : "Activar"

    implicitWidth: sessionRow.implicitWidth + Style.space(20)
    height: Style.space(22)
    radius: Style.space(Style.cornerRadius > 0 ? 7 : 0)
    color: Util.alpha(session.tone, sessionMouse.containsMouse ? 0.24 : 0.14)
    border.width: 1
    border.color: Util.alpha(session.tone, sessionMouse.containsMouse ? 0.55 : 0.34)
    opacity: session.busy ? 0.55 : 1
    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 130 } }
    Behavior on opacity { NumberAnimation { duration: 130 } }

    Row {
      id: sessionRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: session.busy ? "󰑓" : session.glyph
        color: session.tone
        font.family: controls.fontFamily
        font.pixelSize: Style.font.caption
        Behavior on color { ColorAnimation { duration: 130 } }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: session.label
        color: session.tone
        font.family: controls.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        Behavior on color { ColorAnimation { duration: 130 } }
      }
    }

    MouseArea {
      id: sessionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: !session.busy
      cursorShape: Qt.PointingHandCursor
      onClicked: session.activated()
    }
  }
}
