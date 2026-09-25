import QtQuick
import qs.Commons
import qs.Ui
import "../notifications"
import "../Pages.js" as Pages

// Notifications page: the history the notification service has archived, newest
// first, with a clear action. Click-through to the sending app is deliberately
// absent — the service resolves those actions against live notification
// objects, which are not exposed outside it.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  // Ages are text, not a model role; a slow tick keeps them honest without
  // rebuilding rows.
  property int nowTick: 0

  readonly property var entries: history.entries
  readonly property bool empty: entries.length === 0

  NotificationHistory {
    id: history
    active: root.panelActive
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.panelActive
    onTriggered: root.nowTick++
  }

  function refresh() {
    history.refresh()
  }

  function ageOf(timestamp) {
    root.nowTick
    return Pages.relativeAge(timestamp, Date.now())
  }

  // Some senders stringify a structured body into "[object Object]". That is
  // never information, so the row drops it rather than printing the artifact.
  function bodyOf(entry) {
    var body = entry ? entry.body : ""
    if (typeof body !== "string") return ""
    return body === "[object Object]" ? "" : body
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(8)

      PanelSectionHeader {
        id: sectionLabel
        text: "HISTORIAL"
        foreground: root.foreground
        fontFamily: root.fontFamily
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: Math.max(0, parent.width - sectionLabel.implicitWidth - clearButton.implicitWidth - parent.spacing * 2)
        height: 1
      }

      Button {
        id: clearButton
        text: "Limpiar"
        iconText: "󰆴"
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: !root.empty
        onClicked: history.clear()
      }
    }

    PanelSeparator { foreground: root.foreground }

    Text {
      textFormat: Text.PlainText
      visible: root.empty
      width: parent.width
      text: "No hay notificaciones recientes"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      topPadding: Style.space(20)
      bottomPadding: Style.space(20)
    }

    Flickable {
      id: listFlick
      width: parent.width
      height: Math.min(list.implicitHeight, Style.space(380))
      contentWidth: width
      contentHeight: list.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      visible: !root.empty

      Column {
        id: list
        width: listFlick.width
        spacing: Style.space(6)

        Repeater {
          model: root.entries

          BorderSurface {
            id: row
            required property var modelData

            width: list.width
            implicitHeight: rowContent.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.04)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

            Row {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.rightMargin: Style.spacing.rowPaddingX
              spacing: Style.spacing.rowPaddingX

              Text {
                id: glyphText
                textFormat: Text.PlainText
                anchors.top: parent.top
                anchors.topMargin: Style.space(2)
                text: String(row.modelData.glyph || "") !== "" ? row.modelData.glyph : "󰂚"
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              Column {
                width: parent.width - glyphText.width - ageText.width - parent.spacing * 2
                spacing: Style.spacing.xs

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: String(row.modelData.app || "").toUpperCase()
                  color: Qt.darker(root.foreground, 1.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: String(row.modelData.summary || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  visible: text !== ""
                  width: parent.width
                  text: root.bodyOf(row.modelData)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }

              Text {
                id: ageText
                textFormat: Text.PlainText
                anchors.top: parent.top
                anchors.topMargin: Style.space(2)
                text: root.ageOf(row.modelData.timestamp)
                color: Qt.darker(root.foreground, 1.7)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}