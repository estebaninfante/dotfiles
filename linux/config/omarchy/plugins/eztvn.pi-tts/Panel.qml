import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Widget de barra: interruptor maestro de la voz TTS del sistema (`voice
// tts`), con volumen relativo y el registro de mensajes del sistema (lo que
// dijo el agente y las notificaciones que llegaron), para repetir cualquiera.
// Muestra si
// la voz esta activa y la activa/desactiva; como es el mismo `tts.enabled`
// que respetan los agentes, aplica al instante y sin reiniciar Pi. El volumen
// (`voice volume`) y el historial (`voice history`) salen del mismo sistema de
// voz, asi que el panel los controla sin duplicar logica. Clic izquierdo abre
// el panel; derecho/central alterna el interruptor.
Panel {
  id: root

  moduleName: "eztvn.pi-tts"
  ipcTarget: "eztvn.pi-tts"

  readonly property int refreshMs: Math.max(500, Number(cfg("refreshIntervalMs", 2000)))
  readonly property string scriptPath: Qt.resolvedUrl("status.sh").toString().replace("file://", "")

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool ttsEnabled: true
  property string source: ""
  property bool busy: false
  // Volumen relativo (0-1) de la voz TTS sobre el volumen general de salida.
  property real volume: 1.0
  // Registro de mensajes del sistema (voz + notificaciones), mas reciente
  // primero (lo llena status.sh messages).
  property var history: []
  property bool historyLoaded: false
  property int playingIndex: -1
  // Mensajes pendientes de escuchar (buzon).
  property int pending: 0

  readonly property string glyph: root.pending > 0 ? "󰂚" : (root.ttsEnabled ? "󰕾" : "󰖁")
  readonly property string stateLabel: root.ttsEnabled ? "Activado" : "Desactivado"
  readonly property color stateColor: root.ttsEnabled ? root.accent : Qt.darker(root.foreground, 1.6)
  readonly property int historyCount: root.history ? root.history.length : 0
  readonly property string tooltipText: "Voz TTS · " + root.stateLabel + " · " +
    Math.round(root.volume * 100) + "%" +
    (root.pending > 0 ? " · " + root.pending + " pendientes" : "") +
    " · clic derecho: activar/desactivar"

  function cfg(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  function refresh() {
    if (!probe.running) probe.running = true
  }

  function refreshHistory() {
    if (!historyProc.running) historyProc.running = true
  }

  function control(action) {
    if (root.busy) return
    root.busy = true
    control.cmd = [scriptPath, action]
    if (!control.running) control.running = true
  }

  function toggleEnabled() { root.control(root.ttsEnabled ? "disable" : "enable") }

  // El slider informa el valor crudo; persistirlo escribe `voice volume`.
  function setVolume(value) {
    var next = Math.max(0, Math.min(1, value))
    if (Math.abs(next - root.volume) < 0.001) return
    root.volume = next
    volumeProc.cmd = [root.scriptPath, "volume-set", next.toFixed(3)]
    if (!volumeProc.running) volumeProc.running = true
  }

  function playEntry(index) {
    if (index < 0 || index >= root.historyCount) return
    var entry = root.history[index]
    if (!entry) return
    root.playingIndex = index
    playProc.cmd = [root.scriptPath, "repeat-entry", String(index + 1)]
    if (!playProc.running) playProc.running = true
  }

  function repeatLast() {
    if (root.historyCount === 0) return
    root.playingIndex = 0
    playProc.cmd = [root.scriptPath, "repeat", "1"]
    if (!playProc.running) playProc.running = true
  }

  function applyStatus(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text).trim()) } catch (e) { parsed = null }
    if (!parsed) return
    if (parsed.state) root.ttsEnabled = String(parsed.state) === "enabled"
    if (parsed.source) root.source = String(parsed.source)
    if (typeof parsed.volume === "number") root.volume = parsed.volume
    if (typeof parsed.pending === "number") root.pending = parsed.pending
  }

  function playInbox() {
    if (root.pending === 0 || playProc.running) return
    playProc.cmd = [root.scriptPath, "play-inbox", ""]
    playProc.running = true
  }

  function clearInbox() {
    if (root.pending === 0 || inboxProc.running) return
    inboxProc.running = true
  }

  function applyHistory(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text).trim()) } catch (e) { parsed = null }
    root.history = Array.isArray(parsed) ? parsed : []
    root.historyLoaded = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    root.refresh()
    root.refreshHistory()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // El historial solo se relee con el panel abierto: en segundo plano no hace
  // falta y serian 200 entradas cada pocos segundos.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshHistory()
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

  Process {
    id: volumeProc
    property var cmd: []
    command: cmd
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.refresh()
    }
    onExited: root.refresh()
  }

  Process {
    id: historyProc
    command: [scriptPath, "messages", "200"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyHistory(text)
    }
  }

  Process {
    id: playProc
    property var cmd: []
    command: cmd
    stdout: StdioCollector { waitForEnd: true }
    onExited: { root.playingIndex = -1; root.refresh() }
  }

  Process {
    id: inboxProc
    command: [scriptPath, "clear-inbox"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    slotSize: Style.bar.statusSlot
    fontSize: Style.bar.iconCanvas
    tooltipText: root.tooltipText
    active: root.ttsEnabled || root.pending > 0
    useActiveColor: true
    activeColor: root.pending > 0 ? root.accent : root.stateColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) {
        root.toggleEnabled()
      } else {
        root.toggle()
      }
    }
  }

  // Badge del buzon: cuantos mensajes hay por escuchar (visual sutil).
  Rectangle {
    id: badge
    visible: root.pending > 0
    z: 10
    width: Math.max(badgeText.implicitWidth + Style.space(6), Style.space(13))
    height: Style.space(13)
    radius: height / 2
    color: root.accent
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: Style.space(1)
    anchors.topMargin: Style.space(1)

    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.pending > 99 ? "99+" : String(root.pending)
      color: Color.background
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === " " || text === "t" || text === "T") root.toggleEnabled()
        else if (text === "b" || text === "B") root.playInbox()
        else if (text === "l" || text === "L") root.repeatLast()
        else if (text === "r" || text === "R") { root.refresh(); root.refreshHistory() }
        else if (text === "+" || text === "=") root.setVolume(root.volume + 0.05)
        else if (text === "-" || text === "_") root.setVolume(root.volume - 0.05)
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scroll.availableWidth
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Voz (TTS)"
            meta: root.stateLabel +
                  (root.pending > 0 ? " · " + root.pending + " sin escuchar" : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: column.width
            spacing: Style.space(12)

            Column {
              width: parent.width - toggle.implicitWidth - parent.spacing
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.ttsEnabled ? "Voz del sistema activa" : "Voz del sistema silenciada"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Anuncios hablados de los agentes (Pi, opencode…)."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            ToggleSwitch {
              id: toggle
              checked: root.ttsEnabled
              busy: root.busy
              foreground: root.foreground
              anchors.verticalCenter: parent.verticalCenter
              onToggled: root.toggleEnabled()
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(volumeHeader.implicitHeight, volumePercent.implicitHeight)

              PanelSectionHeader {
                id: volumeHeader
                text: "VOLUMEN DE LA VOZ"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: volumePercent
                textFormat: Text.PlainText
                text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : root.volume) * 100) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: volumeSlider
              bar: root.bar
              width: parent.width
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.volume
              onMoved: function(v) { root.volume = v }
              onReleased: function(v) { root.setVolume(v) }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Relativo al volumen general. El historial de abajo se reproduce a este nivel."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Row {
            width: column.width
            spacing: Style.space(8)

            Button {
              text: root.ttsEnabled ? "Desactivar" : "Activar"
              enabled: !root.busy
              onClicked: root.toggleEnabled()
            }

            Button {
              text: "Escuchar buzón" + (root.pending > 0 ? " (" + root.pending + ")" : "")
              enabled: root.pending > 0
              onClicked: root.playInbox()
            }

            Button {
              text: "Repetir última"
              enabled: root.historyCount > 0
              onClicked: root.repeatLast()
            }

            Button {
              text: "Vaciar buzón"
              enabled: root.pending > 0
              onClicked: root.clearInbox()
            }

            Button {
              text: "Estado"
              onClicked: { root.refresh(); root.refreshHistory() }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(historyHeader.implicitHeight, historyCountText.implicitHeight)

            PanelSectionHeader {
              id: historyHeader
              text: "MENSAJES"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: historyCountText
              textFormat: Text.PlainText
              text: root.historyCount + (root.historyCount === 1 ? " mensaje" : " mensajes")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            width: parent.width
            visible: root.historyLoaded && root.historyCount === 0
            textFormat: Text.PlainText
            text: "Todavía no hay mensajes guardados."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.history

              delegate: Rectangle {
                required property int index
                required property var modelData

                readonly property bool hovered: rowHover.hovered
                readonly property bool playing: root.playingIndex === index

                width: column.width
                height: rowText.implicitHeight + Style.space(10)
                radius: Style.space(6)
                color: playing ? Style.selectedFillFor(root.foreground, Color.accent)
                     : (hovered ? root.hoverFill : "transparent")

                Row {
                  id: rowLayout
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    id: timeText
                    textFormat: Text.PlainText
                    text: Qt.formatDateTime(new Date(modelData.ts), "dd/MM hh:mm")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: rowText
                    width: Math.max(0, rowLayout.width - timeText.width - rowLayout.spacing)
                    textFormat: Text.PlainText
                    text: (modelData.kind === "voice" || modelData.file ? "󰕾 " : "󰂚 ") +
                          String(modelData.text || "").replace(/\s+/g, " ")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                HoverHandler { id: rowHover }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.playEntry(index)
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "T · voz   ·   B · escuchar buzón   ·   + / − · volumen   ·   L · repetir última   ·   R · recargar   ·   clic en un mensaje · repetirlo"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
