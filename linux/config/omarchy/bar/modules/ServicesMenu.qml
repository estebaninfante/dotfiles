import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: menu

  property var module

  readonly property bool open: module ? module.menuOpen : false
  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color unknown: module ? module.unknownColor : Color.muted
  readonly property color globalColor: module ? module.globalColor : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family

  spacing: Style.space(11)

  opacity: 0
  y: -Style.space(5)
  states: [
    State {
      name: "shown"
      when: menu.open
      PropertyChanges { target: menu; opacity: 1; y: 0 }
    }
  ]
  transitions: Transition {
    NumberAnimation { properties: "opacity,y"; duration: 230; easing.type: Easing.OutCubic }
  }

  Item {
    id: header
    width: menu.width
    height: Style.space(42)

    Rectangle {
      id: heroTile
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(38)
      height: width
      radius: Style.space(Style.cornerRadius > 0 ? 11 : 0)
      color: Util.alpha(menu.globalColor, 0.12)
      border.width: 1
      border.color: Util.alpha(menu.globalColor, 0.28)
      Behavior on color { ColorAnimation { duration: 200 } }
      Behavior on border.color { ColorAnimation { duration: 200 } }

      Text {
        anchors.centerIn: parent
        text: "󰒋"
        color: menu.globalColor
        font.family: menu.fontFamily
        font.pixelSize: Style.font.iconLarge
        Behavior on color { ColorAnimation { duration: 200 } }
      }
    }

    Column {
      anchors.left: heroTile.right
      anchors.leftMargin: Style.space(12)
      anchors.right: globalChip.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        text: "SERVICIOS"
        color: menu.fg
        font.family: menu.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        font.letterSpacing: 1.2
      }

      Text {
        width: parent.width
        text: menu.module ? menu.module.globalText : ""
        color: menu.globalColor
        font.family: menu.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: 200 } }
      }
    }

    HeaderChip {
      id: globalChip
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      tone: menu.globalColor
      active: menu.module ? menu.module.activeCount : 0
      total: menu.module ? menu.module.services.length : 0
      pulse: menu.module ? menu.module.busySvc !== "" : false
    }
  }

  Rectangle {
    width: menu.width
    height: Style.space(1)
    color: Util.alpha(menu.fg, 0.08)
  }

  Column {
    id: rows
    width: menu.width
    spacing: Style.space(8)

    Repeater {
      model: menu.module ? menu.module.services : []

      ServiceCard {
        module: menu.module
      }
    }
  }

  Item {
    width: menu.width
    height: Style.space(14)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "Inicio = arranque automático"
      color: Util.alpha(menu.fg, 0.4)
      font.family: menu.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "sesión · reinicio"
      color: Util.alpha(menu.fg, 0.3)
      font.family: menu.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component HeaderChip: Rectangle {
    id: chip

    property color tone: menu.fg
    property int active: 0
    property int total: 0
    property bool pulse: false

    implicitWidth: chipRow.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: height / 2
    color: Util.alpha(chip.tone, 0.13)
    border.width: 1
    border.color: Util.alpha(chip.tone, 0.32)
    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Rectangle {
        id: chipDot
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7)
        height: width
        radius: width / 2
        color: chip.tone
        Behavior on color { ColorAnimation { duration: 200 } }

        SequentialAnimation on opacity {
          running: chip.pulse
          loops: Animation.Infinite
          NumberAnimation { to: 0.25; duration: 450; easing.type: Easing.OutQuad }
          NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
          onRunningChanged: if (!running) chipDot.opacity = 1
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.active + "/" + chip.total
        color: chip.tone
        font.family: menu.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        Behavior on color { ColorAnimation { duration: 200 } }
      }
    }
  }
}
