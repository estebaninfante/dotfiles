import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Contenido del submenú de lan-mouse para empotrarlo dentro del menú de
// servicios (mismo popup). Reusa el lienzo de disposición y las filas del
// plugin con su propio estado.
Item {
  id: detail

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool daemonOk: state.daemonOk
  readonly property bool hasClients: state.hasClients
  readonly property var localScreen: Model.localDisplay(state.monitors)
  readonly property var remotePeer: hasClients
    ? Object.assign(Model.peerDisplay(state.primaryHost), { position: state.effectivePosition })
    : null
  readonly property var peers: remotePeer ? [remotePeer] : []

  readonly property string statusText: !daemonOk
    ? (state.daemonError !== "" ? state.daemonError : "Revisa el servicio lan-mouse")
    : state.lastError !== ""
      ? state.lastError
      : !hasClients
        ? "Sin clientes en ~/.config/lan-mouse/config.toml"
        : state.busy
          ? "Aplicando · " + Model.positionLabel(state.effectivePosition)
          : "Arrastra el equipo a un borde y suelta: se aplica al instante"
  readonly property color statusColor: (!daemonOk || state.lastError !== "")
    ? Color.urgent
    : Color.muted

  implicitHeight: content.implicitHeight
  width: parent ? parent.width : implicitWidth

  LanMouseState {
    id: state
    pollSeconds: 4
  }

  Column {
    id: content
    width: detail.width
    spacing: Style.space(12)

    PanelSectionHeader {
      text: "DISPOSICIÓN"
      foreground: detail.foreground
      fontFamily: detail.fontFamily
    }

    ArrangementCanvas {
      width: parent.width
      localDisplay: detail.localScreen
      peers: detail.peers
      interactive: detail.daemonOk && detail.hasClients && !state.busy
      foreground: detail.foreground
      fontFamily: detail.fontFamily
      onDropRequested: function(zone) { state.setPosition(zone) }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: detail.statusText
      color: detail.statusColor
      font.family: detail.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    PanelSeparator { foreground: detail.foreground }

    ClientRow {
      width: parent.width
      client: state.primary
      busy: state.busy
      foreground: detail.foreground
      fontFamily: detail.fontFamily
      onActiveChosen: function(active) { state.setActive(active) }
    }

    PanelSeparator { foreground: detail.foreground }

    Loader {
      id: syncLoader
      width: parent.width
      source: "SyncScreensRow.qml"
    }

    Binding {
      target: syncLoader.item
      property: "foreground"
      value: detail.foreground
      when: syncLoader.status === Loader.Ready
    }

    Binding {
      target: syncLoader.item
      property: "fontFamily"
      value: detail.fontFamily
      when: syncLoader.status === Loader.Ready
    }
  }
}
