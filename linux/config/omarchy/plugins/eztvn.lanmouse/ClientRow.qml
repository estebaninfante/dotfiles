import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var client: null
  property bool busy: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal activeChosen(bool active)

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(10)

  readonly property bool clientActive: !!(client && client.active)
  readonly property bool fromConfig: !!(client && client.source === "config")
  readonly property string endpoint: client
    ? (String(client.port || "") !== "" ? client.host + ":" + client.port : String(client.host || ""))
    : ""
  readonly property string stateText: !client
    ? "sin cliente configurado"
    : fromConfig
      ? "config.toml \u00b7 " + Model.positionLabel(client.position)
      : Model.positionLabel(client.position) + (clientActive ? " \u00b7 activo" : " \u00b7 inactivo")
  readonly property color stateColor: fromConfig
    ? Color.urgent
    : (clientActive ? Color.accent : Color.muted)

  Item {
    width: parent.width
    implicitHeight: Math.max(labels.implicitHeight, dot.height)

    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: dot.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.endpoint
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.stateText
        elide: Text.ElideRight
        color: root.stateColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      id: dot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: Style.space(8)
      radius: width / 2
      opacity: root.busy ? 0.5 : 1
      color: root.stateColor

      Behavior on color {
        ColorAnimation { duration: 140 }
      }

      Behavior on opacity {
        NumberAnimation { duration: 140 }
      }
    }
  }

  Toggle {
    width: parent.width
    label: "Cliente activo"
    checked: root.clientActive
    enabled: !root.busy && !root.fromConfig && !!root.client
    onClicked: root.activeChosen(!root.clientActive)
  }
}
