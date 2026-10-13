pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var panel: null
  readonly property color foreground: panel ? panel.barForeground : Color.foreground
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family
  readonly property var sessions: panel ? panel.sessions : []
  readonly property real nowSec: panel ? panel.nowSec : 0
  readonly property bool loaded: panel ? panel.loaded : false
  readonly property bool missing: panel ? panel.missing : false

  width: parent ? parent.width : 100
  spacing: Style.space(8)

  PanelSectionHeader {
    text: "SESIONES"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    visible: !root.loaded
    text: "Consultando sesiones tmux…"
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    visible: root.loaded && root.missing
    text: "tmux no está instalado en esta máquina."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    visible: root.loaded && !root.missing && root.sessions.length === 0
    text: "No hay sesiones tmux abiertas. Crea una desde una terminal con «tmux new -s nombre»."
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.sessions
    delegate: SessionRow { width: root.width }
  }

  component SessionRow: Item {
    id: row

    required property var modelData
    readonly property var session: modelData
    readonly property bool inUse: session && session.attached === true
    readonly property color foreground: root.foreground
    readonly property string fontFamily: root.fontFamily

    width: parent ? parent.width : implicitWidth
    height: nameCol.implicitHeight + Style.space(18)

    function visit() {
      if (root.panel) root.panel.attach(row.session ? String(row.session.name) : "")
    }

    function kill() {
      if (root.panel && row.session) root.panel.requestKill(String(row.session.name))
    }

    Rectangle {
      id: rowBg
      anchors.fill: parent
      radius: Style.cornerRadius
      color: hover.containsMouse
        ? Style.hoverFillFor(root.foreground, Color.accent)
        : Util.alpha(root.foreground, 0.05)
      border.color: row.inUse
        ? Util.alpha(Color.urgent, 0.62)
        : Util.alpha(root.foreground, 0.12)
      border.width: 1

      Behavior on color {
        ColorAnimation { duration: 120 }
      }
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.visit()
    }

    Column {
      id: nameCol
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.right: rowActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.session ? String(row.session.name) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: Model.rowMeta(row.session, root.nowSec)
        color: row.inUse ? Color.urgent : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: rowActions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Button {
        text: "Ver"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        horizontalPadding: Style.space(12)
        verticalPadding: Style.space(8)
        implicitHeight: Math.max(32, Style.space(34))
        tooltipText: "Adjuntar «" + (row.session ? String(row.session.name) : "") + "» en una terminal"
        onClicked: row.visit()
      }

      Button {
        text: "Eliminar"
        bordered: true
        foreground: Color.urgent
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        horizontalPadding: Style.space(12)
        verticalPadding: Style.space(8)
        implicitHeight: Math.max(32, Style.space(34))
        tooltipText: row.inUse
          ? "«" + (row.session ? String(row.session.name) : "") + "» está en uso: confirmación reforzada"
          : "Eliminar «" + (row.session ? String(row.session.name) : "") + "» (pide confirmación)"
        onClicked: row.kill()
      }
    }
  }
}
