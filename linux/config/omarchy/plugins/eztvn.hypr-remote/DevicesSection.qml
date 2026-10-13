pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var panel: null
  readonly property var status: panel ? panel.status : null
  readonly property color foreground: panel ? panel.barForeground : Color.foreground
  readonly property color urgentColor: panel ? panel.urgentColor : Color.urgent
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property var rows: panel ? panel.deviceRows : []
  readonly property bool down: !status || !status.running
  readonly property bool busy: panel ? panel.busy : false

  width: parent ? parent.width : 100
  spacing: Style.space(8)

  PanelSectionHeader {
    text: "TELÉFONOS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    visible: root.down
    text: root.status && root.status.unit === "active"
      ? "Sin API de control: la lista de teléfonos no está disponible."
      : "Servicio detenido: la lista de teléfonos no está disponible."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    visible: !root.down && root.rows.length === 0
    text: "Aún no hay teléfonos emparejados. Empareja uno con el QR de arriba."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.down ? [] : root.rows
    delegate: DeviceRow {
      width: root.width
    }
  }

  Button {
    text: "Desemparejar todos"
    visible: !root.down && root.status.paired > 0
    enabled: !root.busy
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    bordered: true
    onClicked: if (root.panel) root.panel.requestConfirm(
      "unpairAll",
      "¿Desemparejar los " + root.status.paired + " teléfonos? Tendrás que emparejarlos otra vez.",
      "Última confirmación: se borran TODOS los teléfonos guardados en hypr-remote."
    )
  }

  component DeviceRow: Item {
    id: devRow
    required property var modelData
    readonly property var dev: modelData

    width: parent ? parent.width : implicitWidth
    height: rowContent.implicitHeight

    readonly property bool rowBusy: root.busy
    readonly property string statusLine: {
      var seen = dev.connected ? "conectado ahora" : "última vez " + dev.seenText
      if (dev.pairedText && dev.pairedText !== "—") seen += " · emparejado " + dev.pairedText
      return seen
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Math.max(nameCol.implicitHeight, forgetButton.height)

      Column {
        id: nameCol
        anchors.left: parent.left
        anchors.right: forgetButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: devRow.dev.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: devRow.statusLine
          color: devRow.dev.connected ? root.foreground : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: forgetButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅙"
        tooltipText: "Dejar de confiar en " + devRow.dev.name
        foreground: root.foreground
        hoverColor: root.urgentColor
        fontFamily: root.fontFamily
        enabled: !devRow.rowBusy && devRow.dev.id !== ""
        onClicked: if (root.panel) root.panel.control("forget", devRow.dev.id)
      }
    }
  }
}
