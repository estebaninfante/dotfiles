import QtQuick
import qs.Commons
import qs.Ui
import "../Pages.js" as Pages

// Index page: every dashboard page as a row, with the current one marked.
// Clicking a row asks the panel to navigate; this page owns no state.
Item {
  id: root

  property bool panelActive: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string activePage: "calendar"

  signal pageRequested(string id)

  readonly property var pages: Pages.allPages()

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.pages

      BorderSurface {
        id: rowItem
        required property var modelData

        readonly property bool current: root.activePage === modelData.id

        width: column.width
        implicitHeight: rowContent.implicitHeight + Style.space(18)
        radius: Style.cornerRadius
        borderSpec: Border.controlSpec(
          root.activePage === modelData.id ? "selected"
            : (rowMouse.containsMouse ? "hover-cursor" : "normal"),
          root.foreground, Color.accent)
        color: Style.controlFill(false, rowMouse.containsMouse, root.foreground, Color.accent)

        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
          id: rowContent
          anchors.left: parent.left
          anchors.right: chevron.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.spacing.rowPaddingX
          anchors.rightMargin: Style.spacing.rowPaddingX
          spacing: Style.spacing.rowPaddingX

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.modelData.glyph
            color: rowItem.current
              ? Style.selectedStateColor(root.foreground, Color.accent)
              : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Column {
            width: parent.width - parent.children[0].width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: rowItem.modelData.title
              color: rowItem.current
                ? Style.selectedStateColor(root.foreground, Color.accent)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              visible: String(rowItem.modelData.description || "") !== ""
              width: parent.width
              text: rowItem.modelData.description
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Text {
          id: chevron
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.rowPaddingX
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅂"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pageRequested(rowItem.modelData.id)
        }
      }
    }
  }
}
