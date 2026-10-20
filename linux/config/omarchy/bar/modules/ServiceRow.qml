import QtQuick
import qs.Commons
import qs.Ui

// Fila compacta y navegable de la lista de servicios. El clic abre el
// submenú específico del servicio dentro del mismo popup.
Rectangle {
  id: row

  required property var modelData
  property var module
  property var motion

  signal activated(string svc)

  readonly property var svc: modelData
  readonly property bool busy: module ? module.busySvc === svc.svc : false
  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color tone: module ? (busy ? module.warnColor : module.healthColor(svc)) : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family
  readonly property string stateLabel: module ? module.statusLabel(svc) : ""
  readonly property bool starts: module ? module.isEnabled(svc.enabled) : false
  readonly property bool hasPanel: module ? module.hasExtraPanel(svc.svc) : false

  width: parent ? parent.width : 0
  implicitHeight: Style.space(46)
  radius: Style.space(Style.cornerRadius > 0 ? 9 : 0)
  color: hover.hovered ? Util.alpha(fg, 0.075) : Util.alpha(fg, 0.035)
  border.width: 1
  border.color: Util.alpha(tone, hover.hovered ? 0.32 : 0.10)

  Behavior on color {
    ColorAnimation {
      duration: row.motion ? row.motion.fast : 120
      easing.type: row.motion ? row.motion.standard : Easing.OutCubic
    }
  }
  Behavior on border.color {
    ColorAnimation {
      duration: row.motion ? row.motion.base : 180
      easing.type: row.motion ? row.motion.standard : Easing.OutCubic
    }
  }

  HoverHandler { id: hover }

  Rectangle {
    id: led
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(8)
    height: width
    radius: width / 2
    color: row.tone
    Behavior on color { ColorAnimation { duration: row.motion ? row.motion.base : 180 } }

    SequentialAnimation on opacity {
      running: row.busy && !(row.motion && row.motion.reduced)
      loops: Animation.Infinite
      NumberAnimation { to: 0.25; duration: 450; easing.type: Easing.OutQuad } // pulso
      NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutQuad } // pulso
      onRunningChanged: if (!running) led.opacity = 1
    }
  }

  Column {
    anchors.left: led.right
    anchors.leftMargin: Style.space(10)
    anchors.right: trailing.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.svc.label
      color: row.fg
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.stateLabel + (row.starts ? "  ·  inicio" : "")
      color: row.tone
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      Behavior on color { ColorAnimation { duration: row.motion ? row.motion.base : 180 } }
    }
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: row.hasPanel
      text: "panel"
      color: Util.alpha(row.fg, 0.38)
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: row.busy ? "󰑓" : "󰅂"
      color: hover.hovered ? row.fg : Util.alpha(row.fg, 0.55)
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      // La flecha se adelanta un poco al hover: anticipa que la fila lleva a
      // otro lado (dirección = derecha) sin mover toda la fila.
      x: hover.hovered ? Style.space(2) : 0
      Behavior on x {
        NumberAnimation {
          duration: row.motion ? row.motion.base : 180
          easing.type: row.motion ? row.motion.standard : Easing.OutCubic
        }
      }
      Behavior on color { ColorAnimation { duration: row.motion ? row.motion.fast : 120 } }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.activated(row.svc.svc)
  }
}
