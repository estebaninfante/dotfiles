import QtQuick
import qs.Commons
import qs.Ui

// Shared dashboard header: `‹   Menu   ›`. Chevrons step through the page
// ring; the title in the middle is a button that opens the index page.
//
// Purely presentational — the panel owns page state and navigation.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string title: ""
  property int pageIndex: -1
  property int pageCount: 0

  signal prevRequested()
  signal nextRequested()
  signal menuRequested()

  implicitHeight: row.height + Style.space(10)

  Item {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(prevButton.implicitHeight, titleButton.implicitHeight, nextButton.implicitHeight)

    PanelActionButton {
      id: prevButton
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅁"
      tooltipText: "Página anterior"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      onClicked: root.prevRequested()
    }

    PanelActionButton {
      id: nextButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅂"
      tooltipText: "Página siguiente"
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      onClicked: root.nextRequested()
    }

    Button {
      id: titleButton
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      iconText: "󰍜"
      fontSize: Style.font.title
      iconSize: Style.font.body
      foreground: root.foreground
      fontFamily: root.fontFamily
      tooltipText: "Todas las páginas"
      bordered: true
      onClicked: root.menuRequested()
    }

    // Page position, tucked just inside the next chevron. Quiet enough to
    // read as a caption rather than a control.
    Text {
      textFormat: Text.PlainText
      visible: root.pageCount > 0 && root.pageIndex >= 0
      anchors.right: nextButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: root.pageIndex >= 0 ? (root.pageIndex + 1) + "/" + root.pageCount : ""
      color: Qt.darker(root.foreground, 1.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
  }

  PanelSeparator {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    foreground: root.foreground
  }
}
