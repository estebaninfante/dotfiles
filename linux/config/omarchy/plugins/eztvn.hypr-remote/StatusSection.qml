import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var panel: null
  readonly property var status: panel ? panel.status : null
  readonly property color foreground: panel ? panel.barForeground : Color.foreground
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  width: parent ? parent.width : 100
  spacing: Style.space(8)

  PanelHero {
    title: "hypr-remote"
    meta: Model.stateLabel(root.status)
    detail: root.status && root.status.running ? root.status.connected + "/" + root.status.paired : ""
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoRow {
    label: "Estado"
    value: Model.stateLabel(root.status)
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoRow {
    label: "Tiempo activo"
    value: root.status && root.status.running ? Model.uptimeText(root.status.uptimeSec) : "—"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoRow {
    label: "HTTPS"
    value: Model.httpsText(root.status)
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoRow {
    label: "Teléfonos"
    value: root.status && root.status.running
      ? Model.countsText(root.status)
      : "—"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  InfoRow {
    label: "Versión"
    value: Model.versionText(root.status)
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    visible: !root.status || !root.status.running
    text: root.status && root.status.unit === "active"
      ? "La unidad corre pero el socket de control no responde."
      : "El servicio no está corriendo: arráncalo en la sección Servicio."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
