import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Vista de detalle de un servicio: cabecera, controles genéricos y, si existe,
// el submenú específico del servicio embebido en la misma ventana.
ScrollView {
  id: detail

  property var module
  property var motion
  signal confirmRequested(string action, string message, string second)

  readonly property var svc: module ? module.detailService : null
  readonly property string svcId: svc ? svc.svc : ""
  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color tone: module && svc ? (module.busySvc === svc.svc ? module.warnColor : module.healthColor(svc)) : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family
  readonly property string stateLabel: module && svc ? module.statusLabel(svc) : ""
  readonly property bool starts: module && svc ? module.isEnabled(svc.enabled) : false
  readonly property bool isActive: svc ? svc.state === "active" : false
  readonly property bool busy: module && svc ? module.busySvc === svc.svc : false

  readonly property string pluginSource: {
    if (svcId === "hypr-remote.service") return "../../plugins/eztvn.hypr-remote/Detail.qml"
    if (svcId === "lan-mouse.service") return "../../plugins/eztvn.lanmouse/Detail.qml"
    return ""
  }
  readonly property bool hasPlugin: pluginSource !== ""

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.min(content.implicitHeight, Style.space(560))
  contentWidth: availableWidth
  clip: true
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: content.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

  function handleConfirmed(action) {
    var it = pluginLoader.item
    if (it && it.handleConfirmed) it.handleConfirmed(action)
  }

  function wirePlugin() {
    var it = pluginLoader.item
    if (!it) return
    if ("foreground" in it) it.foreground = Qt.binding(function() { return detail.fg })
    if ("fontFamily" in it) it.fontFamily = Qt.binding(function() { return detail.fontFamily })
    if ("urgentColor" in it) it.urgentColor = Qt.binding(function() {
      return detail.module ? detail.module.downColor : Color.urgent
    })
    if (it.confirmRequested) it.confirmRequested.connect(function(action, message, second) {
      detail.confirmRequested(action, message, second)
    })
  }

  Column {
    id: content
    width: detail.availableWidth
    spacing: Style.space(11)

    Button {
      width: parent.width
      text: "Volver a servicios"
      iconText: "󰁍"
      leftAlign: true
      bordered: true
      foreground: detail.fg
      fontFamily: detail.fontFamily
      fontSize: Style.font.caption
      onClicked: if (detail.module) detail.module.closeDetail()
    }

    PanelSeparator { width: parent.width; foreground: detail.fg }

    Component {
      id: detailIcon

      Text {
        text: detail.svc ? detail.svc.glyph : "󰒋"
        color: detail.tone
        font.family: detail.fontFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    PanelHero {
      width: parent.width
      title: detail.svc ? detail.svc.label : ""
      meta: detail.stateLabel
      detail: detail.starts ? "inicio" : ""
      foreground: detail.fg
      fontFamily: detail.fontFamily
      iconComponent: detailIcon
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: detail.svcId
      color: Util.alpha(detail.fg, 0.5)
      font.family: detail.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Toggle {
      width: parent.width
      label: "Arranque automático"
      description: "Habilitar al iniciar sesión"
      checked: detail.starts
      enabled: !detail.busy
      foreground: detail.fg
      fontFamily: detail.fontFamily
      onClicked: if (detail.module && detail.svc) detail.module.toggleStartup(detail.svcId, detail.svc.enabled)
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Button {
        text: detail.isActive ? "Detener" : "Activar"
        iconText: detail.isActive ? "󰓛" : "󰐊"
        bordered: true
        enabled: !detail.busy
        foreground: detail.isActive
          ? (detail.module ? detail.module.downColor : Color.urgent)
          : (detail.module ? detail.module.okColor : Color.accent)
        fontFamily: detail.fontFamily
        fontSize: Style.font.caption
        onClicked: if (detail.module && detail.svc) detail.module.toggleService(detail.svcId, detail.svc.state)
      }

      Button {
        text: "Reiniciar"
        iconText: "󰑓"
        bordered: true
        enabled: !detail.busy
        foreground: detail.fg
        fontFamily: detail.fontFamily
        fontSize: Style.font.caption
        onClicked: if (detail.module && detail.svc) detail.module.restartService(detail.svcId)
      }

      Button {
        text: "Registros"
        iconText: "󰈈"
        bordered: true
        enabled: !detail.busy
        foreground: detail.fg
        fontFamily: detail.fontFamily
        fontSize: Style.font.caption
        onClicked: if (detail.module) detail.module.openLogs(detail.svcId)
      }
    }

    PanelSeparator {
      width: parent.width
      foreground: detail.fg
      visible: detail.hasPlugin
    }

    Loader {
      id: pluginLoader
      width: parent.width
      height: item ? item.implicitHeight : 0
      active: detail.hasPlugin
      source: detail.pluginSource
      onLoaded: detail.wirePlugin()
    }
  }
}
