import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// OmniVoz bar widget: mirrors the live state published by the voice agent in
// $XDG_RUNTIME_DIR/omnivoz/status.json. Left click opens this panel, right or
// middle click toggles the background listener (omnivoz-listen).
Panel {
  id: root

  moduleName: "omnivoz.status"
  ipcTarget: "omnivoz.status"

  readonly property string toggleCommand: cfg("toggleCommand", "omnivoz-listen")
  readonly property string configPathText: cfg("configPath", "~/.config/omnivoz/config.json")
  readonly property int refreshMs: Math.max(500, Number(cfg("refreshIntervalMs", 2000)))
  readonly property string statusPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omnivoz/status.json"
  readonly property int staleMs: 45000

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string state: "off"
  property string stateLabel: "Sin agente"
  property string glyph: "󰍬"
  property color stateColor: Qt.darker(foreground, 1.5)
  property var infoRows: []

  // Last turn: what it heard, understood and answered.
  property string transcript: ""
  property string understood: ""
  property string result: ""
  property var turnRows: []
  // Desktop snapshot the decision model was given.
  property var ctxRows: []
  property string lastUpdateText: ""

  readonly property bool hasTurn: root.turnRows.length > 0

  readonly property string tooltipText: "OmniVoz · " + root.stateLabel +
    (root.transcript.length > 0 ? " · «" + root.transcript + "»" : "") +
    (root.state === "off" ? " · clic derecho para activar" : " · clic derecho para pausar")

  function cfg(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  function glyphFor(s) {
    if (s === "listening") return "󰍬"
    if (s === "thinking") return "󰔟"
    if (s === "acting") return "󰌌"
    if (s === "done") return "󰄬"
    if (s === "error") return "󰅚"
    return "󰍬"
  }

  function colorFor(s) {
    if (s === "thinking" || s === "acting" || s === "error") return root.urgent
    if (s === "idle" || s === "off") return Qt.darker(root.foreground, 1.5)
    return root.foreground
  }

  function refresh() {
    if (!reader.running) reader.running = true
  }

  function applySnapshot(text) {
    var parsed = null
    try { parsed = JSON.parse(text) } catch (e) { parsed = null }

    var fresh = parsed && parsed.updatedAt && (Date.now() - Number(parsed.updatedAt) <= root.staleMs)
    if (!fresh) {
      root.state = "off"
      root.stateLabel = "Sin agente"
      root.glyph = glyphFor("off")
      root.stateColor = colorFor("off")
      root.infoRows = []
      root.transcript = ""
      root.understood = ""
      root.result = ""
      root.turnRows = []
      root.ctxRows = []
      root.lastUpdateText = ""
      return
    }

    var s = parsed.state || "idle"
    root.state = s
    root.stateLabel = parsed.label || s
    root.glyph = glyphFor(s)
    root.stateColor = colorFor(s)

    var rows = []
    if (parsed.info) {
      for (var key in parsed.info) rows.push({ "k": key, "v": String(parsed.info[key]) })
    }
    root.infoRows = rows

    var activity = parsed.activity || {}
    root.transcript = activity.transcript || ""
    root.understood = activity.understood || ""
    root.result = activity.result || (activity.say || "")

    var tr = []
    if (activity.intent) tr.push({ "k": "Intención", "v": String(activity.intent) })
    if (root.transcript.length > 0) tr.push({ "k": "Transcripción", "v": root.transcript })
    if (root.understood.length > 0) tr.push({ "k": "Entendido", "v": root.understood })
    if (root.result.length > 0) tr.push({ "k": "Resultado", "v": root.result })
    root.turnRows = tr

    var ctx = parsed.context
    var cr = []
    if (ctx) {
      cr.push({ "k": "Ventana activa", "v": ctx.active || "—" })
      cr.push({ "k": "Mouse sobre", "v": ctx.mouse || "—" })
      cr.push({ "k": "Workspace", "v": String(ctx.workspace) + (ctx.openWindows ? " · " + ctx.openWindows + " ventanas" : "") })
      cr.push({ "k": "Última app", "v": ctx.lastApp || "—" })
      if (ctx.focus) cr.push({ "k": "Foco", "v": ctx.focus })
    }
    root.ctxRows = cr

    if (parsed.updatedAt) {
      var d = new Date(Number(parsed.updatedAt))
      root.lastUpdateText = d.toTimeString().slice(0, 8)
    }
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
    id: reader
    command: ["cat", root.statusPath]
    stdout: StdioCollector {
      onStreamFinished: root.applySnapshot(this.text)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: root.tooltipText
    active: root.state !== "idle" && root.state !== "off"
    useActiveColor: true
    activeColor: root.stateColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) {
        if (root.toggleCommand.length > 0 && root.bar) root.bar.run(root.toggleCommand)
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
            title: "OmniVoz"
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
            text: root.state === "off"
              ? "El agente de voz no está corriendo. Clic derecho en el icono de la barra para activarlo."
              : ("Escucha en " + root.toggleCommand + " · clic derecho para pausar")
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "CONFIGURACIÓN ACTIVA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.infoRows
            delegate: Row {
              width: body.width
              spacing: Style.space(8)

              Text {
                width: Style.space(96)
                text: modelData.k
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                text: modelData.v
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Text {
            visible: root.infoRows.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: "Sin datos todavía: arranca el agente y el estado aparecerá aquí."
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "ÚLTIMA INTERACCIÓN"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: !root.hasTurn
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: root.lastUpdateText.length > 0
              ? ("Sin dictado reciente · estado actualizado a las " + root.lastUpdateText)
              : "Sin dictado reciente."
          }

          Repeater {
            model: root.turnRows
            delegate: Row {
              width: body.width
              spacing: Style.space(8)

              Text {
                width: Style.space(96)
                text: modelData.k
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                width: body.width - Style.space(96) - Style.space(8)
                wrapMode: Text.WordWrap
                text: modelData.v
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "CONTEXTO DEL ESCRITORIO"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            text: "Lo que OmniVoz le entrega al modelo antes de decidir."
          }

          Repeater {
            model: root.ctxRows
            delegate: Row {
              width: body.width
              spacing: Style.space(8)

              Text {
                width: Style.space(96)
                text: modelData.k
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                width: body.width - Style.space(96) - Style.space(8)
                wrapMode: Text.WordWrap
                text: modelData.v
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Text {
            visible: root.ctxRows.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: "Sin contexto todavía: llegará con el próximo dictado."
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "ARCHIVOS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: root.configPathText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            text: root.statusPath
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            text: "R · recargar estado"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
