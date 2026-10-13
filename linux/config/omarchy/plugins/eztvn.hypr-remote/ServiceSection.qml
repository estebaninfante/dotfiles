import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var panel: null
  readonly property var status: panel ? panel.status : null
  readonly property color foreground: panel ? panel.barForeground : Color.foreground
  readonly property color urgentColor: panel ? panel.urgentColor : Color.urgent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property bool busy: panel ? panel.busy : false
  readonly property string lastError: panel && panel.monitor ? panel.monitor.lastError : ""
  readonly property string unitState: Model.unitState(status)

  width: parent ? parent.width : 100
  spacing: Style.space(8)

  PanelSectionHeader {
    text: "SERVICIO"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoRow {
    label: "Unidad"
    value: "hypr-remote.service · " + root.unitState
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    visible: root.lastError !== ""
    text: root.lastError
    color: root.urgentColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Button {
      text: root.status && root.status.running ? "Detener" : "Iniciar"
      enabled: !root.busy
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      bordered: true
      onClicked: if (root.panel) root.panel.control(root.status && root.status.running ? "stop" : "start")
    }

    Button {
      text: "Reiniciar"
      enabled: !root.busy
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      bordered: true
      onClicked: if (root.panel) root.panel.control("restart")
    }

    Button {
      text: "Ver logs"
      enabled: !root.busy
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      bordered: true
      onClicked: if (root.panel) root.panel.openLogs()
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "Iniciar/Detener/Reiniciar usan systemctl --user; el estado de arriba se refresca solo."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
