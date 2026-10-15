import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "eztvn.lanmouse"
  ipcTarget: "eztvn.lanmouse"

  readonly property int refreshSeconds: Math.max(1, Math.min(60, Number(setting("refreshSeconds", 4)) || 4))
  readonly property bool verticalBar: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real hPad: Style.spaceReal(8.75)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool daemonOk: state.daemonOk
  readonly property bool hasClients: state.hasClients
  readonly property var localScreen: Model.localDisplay(state.monitors)
  readonly property var remotePeer: hasClients
    ? Object.assign(Model.peerDisplay(state.primaryHost), { position: state.effectivePosition })
    : null
  readonly property var peers: remotePeer ? [remotePeer] : []
  readonly property string chipGlyph: Model.positionGlyph(state.effectivePosition)
  readonly property color chipColor: !daemonOk
    ? Color.urgent
    : (state.primaryActive ? Color.accent : Color.muted)
  readonly property string chipTooltip: !daemonOk
    ? "lan-mouse \u00b7 daemon no responde"
    : hasClients
      ? "lan-mouse \u00b7 " + state.primaryEndpoint + " \u00b7 " + Model.positionLabel(state.effectivePosition) + (state.primaryActive ? " \u00b7 activo" : " \u00b7 inactivo")
      : "lan-mouse \u00b7 sin clientes"
  readonly property string heroMeta: !daemonOk
    ? "daemon lan-mouse no responde"
    : !hasClients
      ? "sin clientes configurados"
      : state.localIp !== ""
        ? state.localIp + " \u00b7 " + state.primaryHost
        : state.primaryHost
  readonly property string statusText: !daemonOk
    ? (state.daemonError !== "" ? state.daemonError : "Revisa el servicio lan-mouse")
    : state.lastError !== ""
      ? state.lastError
      : !hasClients
        ? "Sin clientes en ~/.config/lan-mouse/config.toml"
        : state.busy
          ? "Aplicando \u00b7 " + Model.positionLabel(state.effectivePosition)
          : "Arrastra la laptop a un borde y suelta: se aplica al instante"
  readonly property color statusColor: (!daemonOk || state.lastError !== "")
    ? Color.urgent
    : Color.muted

  implicitWidth: verticalBar ? barSize : measureLabel.implicitWidth + hPad * 2
  implicitHeight: barSize

  LanMouseState {
    id: state
    pollSeconds: root.refreshSeconds
  }

  Text {
    id: measureLabel
    visible: false
    text: root.chipGlyph
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
  }

  Component {
    id: heroGlyph

    Text {
      textFormat: Text.PlainText
      text: root.chipGlyph
      color: root.chipColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.display

      Behavior on color {
        ColorAnimation { duration: 140 }
      }
    }
  }

  Component {
    id: heroDot

    Rectangle {
      width: Style.space(10)
      height: Style.space(10)
      radius: width / 2
      color: root.chipColor

      Behavior on color {
        ColorAnimation { duration: 140 }
      }
    }
  }

  WidgetButton {
    id: chip
    anchors.fill: parent
    bar: root.bar
    text: root.chipGlyph
    fontSize: Style.font.subtitle
    foreground: root.chipColor
    horizontalMargin: 0
    tooltipText: root.chipTooltip
    onPressed: function(button) {
      if (button === Qt.RightButton) state.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: chip
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "lan-mouse"
          meta: root.heroMeta
          foreground: root.barForeground
          fontFamily: root.fontFamily
          iconComponent: heroGlyph
          trailingControl: heroDot
        }

        PanelSeparator {
          foreground: root.barForeground
        }

        PanelSectionHeader {
          text: "DISPOSICI\u00d3N"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        ArrangementCanvas {
          width: parent.width
          localDisplay: root.localScreen
          peers: root.peers
          interactive: root.daemonOk && root.hasClients && !state.busy
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onDropRequested: function(zone) { state.setPosition(zone) }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.statusText
          color: root.statusColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        PanelSeparator {
          foreground: root.barForeground
        }

        ClientRow {
          width: parent.width
          client: state.primary
          busy: state.busy
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onActiveChosen: function(active) { state.setActive(active) }
        }

        PanelSeparator {
          foreground: root.barForeground
        }

        Loader {
          id: syncLoader
          width: parent.width
          source: "SyncScreensRow.qml"
        }

        Text {
          visible: syncLoader.status === Loader.Error
          width: parent.width
          textFormat: Text.PlainText
          text: "Better Displays Pro no est\u00e1 instalado: sin sincronizaci\u00f3n local"
          color: Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Binding {
          target: syncLoader.item
          property: "foreground"
          value: root.barForeground
          when: syncLoader.status === Loader.Ready
        }

        Binding {
          target: syncLoader.item
          property: "fontFamily"
          value: root.fontFamily
          when: syncLoader.status === Loader.Ready
        }
      }
    }
  }

  onOpenedChanged: {
    if (!opened) return
    state.refresh()
    state.refreshMonitors()
  }
}
