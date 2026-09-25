import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// talk-command bar widget: shows whether the voice wake-word service is
// listening, toggles it (systemctl --user start/stop) and surfaces the live
// keyword count, engine, last trigger and dashboard URL.
Panel {
  id: root

  moduleName: "talk-command.status"
  ipcTarget: "talk-command.status"

  readonly property string serviceName: cfg("serviceName", "talk-command.service")
  readonly property string dashboardUrl: cfg("dashboardUrl", "http://127.0.0.1:8787")
  readonly property int refreshMs: Math.max(500, Number(cfg("refreshIntervalMs", 2000)))
  readonly property string scriptPath: Qt.resolvedUrl("status.sh").toString().replace("file://", "")

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string state: "disabled"
  property int keywordCount: 0
  property string engine: "acoustic"
  property string lastTriggerText: ""
  property bool busy: false

  readonly property bool listening: root.state === "active"
  readonly property string glyph: root.listening ? "󰗅" : "󰍭"
  readonly property color stateColor: root.listening ? root.accent : Qt.darker(root.foreground, 1.6)
  readonly property string stateLabel: {
    if (root.state === "active") return "Escuchando"
    if (root.state === "inactive") return "Pausado"
    return "Deshabilitado"
  }
  readonly property string tooltipText: "talk-command · " + root.stateLabel +
    " · " + root.keywordCount + " keywords" +
    (root.lastTriggerText.length > 0 ? " · ultimo: " + root.lastTriggerText : "") +
    " · clic izquierdo: panel · clic derecho: activar/pausar"

  function cfg(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  function refresh() {
    if (!probe.running) probe.running = true
  }

  function control(action) {
    if (root.busy) return
    root.busy = true
    control.cmd = [scriptPath, action]
    if (!control.running) control.running = true
  }

  function applyStatus(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text).trim()) } catch (e) { parsed = null }
    if (!parsed) return
    if (parsed.state) root.state = String(parsed.state)
    root.keywordCount = Number(parsed.keywords) || 0
    if (parsed.engine) root.engine = String(parsed.engine)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    root.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: probe
    command: [scriptPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: control
    property var cmd: []
    command: cmd
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        root.refresh()
      }
    }
    onExited: root.busy = false
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: root.tooltipText
    active: root.listening
    useActiveColor: true
    activeColor: root.stateColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) {
        root.control("toggle")
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        if (text === " " || text === "t" || text === "T") root.control("toggle")
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "talk-command"
            meta: root.stateLabel
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            text: root.listening
              ? "Wake words activos. Clic derecho en el icono (o T) para pausar."
              : "Escucha en pausa. Clic derecho en el icono (o T) para activar."
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "ESTADO"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: body.width
            spacing: Style.space(8)

            Text {
              width: Style.space(120)
              text: "Servicio"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: root.stateLabel + "  (" + root.serviceName + ")"
              color: root.listening ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            width: body.width
            spacing: Style.space(8)

            Text {
              width: Style.space(120)
              text: "Keywords por voz"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: String(root.keywordCount)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            width: body.width
            spacing: Style.space(8)

            Text {
              width: Style.space(120)
              text: "Motor"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: root.engine
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            width: body.width
            spacing: Style.space(8)

            Text {
              width: Style.space(120)
              text: "Ultimo trigger"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: body.width - Style.space(120) - Style.space(8)
              wrapMode: Text.WordWrap
              text: root.lastTriggerText.length > 0 ? root.lastTriggerText : "—"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "ACCIONES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: body.width
            spacing: Style.space(8)

            Button {
              text: root.listening ? "Pausar" : "Activar"
              enabled: !root.busy
              onClicked: root.control("toggle")
            }

            Button {
              text: "Estado"
              onClicked: root.refresh()
            }

            Button {
              text: "Dashboard"
              onClicked: if (root.bar) root.bar.run("xdg-open " + root.dashboardUrl)
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            width: parent.width
            text: root.dashboardUrl
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            text: "T · activar/pausar   ·   R · recargar estado"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
