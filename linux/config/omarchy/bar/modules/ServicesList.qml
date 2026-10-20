import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Página principal del menú: resumen + lista de servicios. La lista muestra
// como máximo seis filas y a partir de ahí hace scroll.
Column {
  id: root
  property var module
  property var motion
  signal openRequested(string svc)

  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color globalColor: module ? module.globalColor : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family

  readonly property int maxVisible: module ? module.maxVisibleServices : 6
  readonly property int rowHeight: Style.space(46)
  readonly property int rowSpacing: Style.space(6)

  spacing: Style.space(11)
  width: parent ? parent.width : implicitWidth

  Component {
    id: listIcon

    Text {
      text: "󰒋"
      color: root.globalColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.iconLarge
    }
  }

  PanelHero {
    width: parent.width
    title: "Servicios"
    meta: module ? module.globalText : ""
    detail: module ? module.activeCount + "/" + module.services.length : ""
    foreground: root.fg
    fontFamily: root.fontFamily
    iconComponent: listIcon
  }

  PanelSeparator { width: parent.width; foreground: root.fg }

  PanelSectionHeader {
    text: "SERVICIOS"
    foreground: root.fg
    fontFamily: root.fontFamily
  }

  ListView {
    id: rows
    width: parent.width
    implicitHeight: Math.min(contentHeight,
      root.maxVisible * root.rowHeight + Math.max(0, root.maxVisible - 1) * root.rowSpacing)
    spacing: root.rowSpacing
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    model: module ? module.services : []
    delegate: ServiceRow {
      width: rows.width
      module: root.module
      motion: root.motion
      onActivated: function(svc) { root.openRequested(svc) }
    }

    ScrollBar.vertical: ScrollBar {
      policy: rows.contentHeight > rows.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Style.space(24)
      visible: rows.count === 0
      horizontalAlignment: Text.AlignHCenter
      text: "Sin servicios configurados"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Item {
    width: parent.width
    height: Style.space(14)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "Toca un servicio para abrir su panel"
      color: Util.alpha(root.fg, 0.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: module && module.services.length > root.maxVisible
        ? "desliza para ver más"
        : (module ? module.startupCount + " en inicio" : "")
      color: Util.alpha(root.fg, 0.3)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
