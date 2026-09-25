import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName: "services"
  property var settings

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Util.alpha(fg, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color okColor: "#9ece6a"
  readonly property color warnColor: "#e0af68"
  readonly property color unknownColor: "#6c7086"
  readonly property color downColor: "#e06c75"

  readonly property var unitIds: [
    "openclaw-gateway.service",
    "app-dev.lizardbyte.app.Sunshine.service",
    "voice-daemon.service",
    "lan-mouse.service"
  ]

  property string ocState: ""
  property string sunState: ""
  property string ttsState: ""
  property string lanState: ""
  property string ocEnabled: ""
  property string sunEnabled: ""
  property string ttsEnabled: ""
  property string lanEnabled: ""

  property string busySvc: ""
  property bool menuOpen: false

  property var manualStopped: ({})

  readonly property var services: [
    { label: "OC", desc: "openclaw", glyph: "󰚩", svc: root.unitIds[0], state: root.ocState, enabled: root.ocEnabled },
    { label: "SUN", desc: "sunshine", glyph: "󰖨", svc: root.unitIds[1], state: root.sunState, enabled: root.sunEnabled },
    { label: "TTS", desc: "voice", glyph: "󰕾", svc: root.unitIds[2], state: root.ttsState, enabled: root.ttsEnabled },
    { label: "LAN", desc: "lan-mouse", glyph: "󰈀", svc: root.unitIds[3], state: root.lanState, enabled: root.lanEnabled }
  ]

  readonly property real hPad: Style.spaceReal(8.75)
  readonly property bool hasData: services.some(function(s) { return s.state !== "" })
  readonly property bool transitioning: services.some(function(s) { return isTransient(s.state) })
  readonly property bool anyDown: services.some(function(s) {
    return isEnabled(s.enabled) && s.state !== "active" && root.manualStopped[s.svc] !== true
  })
  readonly property int activeCount: services.filter(function(s) { return s.state === "active" }).length
  readonly property int startupCount: services.filter(function(s) { return isEnabled(s.enabled) }).length
  readonly property int downCount: services.filter(function(s) {
    return isEnabled(s.enabled) && s.state !== "active" && root.manualStopped[s.svc] !== true
  }).length
  readonly property bool settling: busySvc !== "" || transitioning

  readonly property color ledColor: settling
    ? warnColor
    : (hasData ? (anyDown ? downColor : okColor) : unknownColor)
  readonly property color globalColor: ledColor

  readonly property string globalText: {
    if (!hasData) return "Consultando unidades…"
    if (settling) return "Aplicando cambios…"
    if (downCount > 0) return downCount === 1 ? "1 servicio caído" : downCount + " servicios caídos"
    if (activeCount === services.length) return "Todo al día"
    return activeCount + " de " + services.length + " activos"
  }

  implicitWidth: vertical ? 8 : (triggerRow.implicitWidth + hPad * 2)
  implicitHeight: bar ? bar.barSize : 26

  function open() { menuOpen = true }
  function close() { menuOpen = false }
  function toggle() { menuOpen = !menuOpen }

  function isEnabled(v) { return v === "enabled" || v === "enabled-runtime" }
  function isTransient(s) { return s === "activating" || s === "deactivating" || s === "reloading" }

  function setManual(svc, value) {
    var next = {}
    for (var k in manualStopped) if (k !== svc) next[k] = manualStopped[k]
    if (value) next[svc] = true
    manualStopped = next
  }

  function colorFor(s) {
    if (s === "active") return okColor
    if (isTransient(s)) return warnColor
    if (s === "") return unknownColor
    return downColor
  }

  function labelFor(s) {
    if (s === "active") return "activo"
    if (s === "inactive") return "detenido"
    if (s === "activating") return "iniciando"
    if (s === "deactivating") return "deteniendo"
    if (s === "reloading") return "recargando"
    if (s === "failed") return "falló"
    if (s === "not-found") return "sin unidad"
    return s === "" ? "desconocido" : s
  }

  function tooltipText() {
    var parts = []
    for (var i = 0; i < services.length; i++) {
      var s = services[i]
      parts.push(s.label + " " + labelFor(s.state) + (isEnabled(s.enabled) ? " (inicio)" : ""))
    }
    return "Servicios: " + parts.join(" · ")
  }

  function run(svc, command) {
    if (!bar || busySvc === svc) return
    busySvc = svc
    bar.run(command)
    settleA.restart()
  }

  function toggleService(svc, state) {
    var stopping = state === "active"
    setManual(svc, stopping)
    run(svc, "systemctl --user " + (stopping ? "stop " : "start ") + svc)
  }

  function restartService(svc) {
    setManual(svc, false)
    run(svc, "systemctl --user restart " + svc)
  }

  function toggleStartup(svc, enabled) {
    run(svc, "systemctl --user " + (isEnabled(enabled) ? "disable " : "enable ") + svc)
  }

  Process {
    id: probe
    command: ["bash", "-lc",
      "systemctl --user is-active " + root.unitIds.join(" ") + " 2>/dev/null; "
      + "echo '::enabled'; systemctl --user is-enabled " + root.unitIds.join(" ") + " 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).replace(/\s+$/, "").split("\n")
        var mark = lines.indexOf("::enabled")
        var act = mark >= 0 ? lines.slice(0, mark) : []
        var en = mark >= 0 ? lines.slice(mark + 1) : []
        root.ocState = (act[0] || "").trim()
        root.sunState = (act[1] || "").trim()
        root.ttsState = (act[2] || "").trim()
        root.lanState = (act[3] || "").trim()
        root.ocEnabled = (en[0] || "").trim()
        root.sunEnabled = (en[1] || "").trim()
        root.ttsEnabled = (en[2] || "").trim()
        root.lanEnabled = (en[3] || "").trim()
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }

  Timer {
    id: settleA
    interval: 500
    onTriggered: {
      if (!probe.running) probe.running = true
      settleB.restart()
    }
  }

  Timer {
    id: settleB
    interval: 2500
    onTriggered: {
      busySvc = ""
      if (!probe.running) probe.running = true
    }
  }

  Rectangle {
    id: triggerBg
    anchors.centerIn: parent
    width: triggerRow.implicitWidth + Style.space(12)
    height: Math.min(Style.space(20), root.height - Style.space(7))
    radius: Style.space(6)
    color: Util.alpha(root.fg, triggerMouse.pressed ? 0.18 : (triggerMouse.containsMouse || root.menuOpen ? 0.11 : 0.0))
    visible: !root.vertical
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  Row {
    id: triggerRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    Rectangle {
      id: led
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: Style.space(8)
      radius: width / 2
      color: root.ledColor
      opacity: root.menuOpen || triggerMouse.containsMouse ? 1.0 : 0.92
      Behavior on color { ColorAnimation { duration: 150 } }
      Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Rectangle {
      id: ledPulse
      anchors.centerIn: led
      width: led.width + Style.space(6)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: root.downColor
      visible: root.anyDown && !root.settling && !root.menuOpen
      opacity: 0.0
      SequentialAnimation on opacity {
        running: ledPulse.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.6; duration: 460; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.0; duration: 460; easing.type: Easing.InQuad }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.menuOpen ? "󰅃" : "󰅀"
      color: Util.alpha(root.fg, triggerMouse.containsMouse || root.menuOpen ? 0.95 : 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    id: triggerMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    onClicked: root.toggle()
    onEntered: if (bar) bar.showTooltip(root, root.tooltipText())
    onExited: if (bar) bar.hideTooltip(root)
  }

  PopupCard {
    id: menu
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(420))
    contentHeight: menu.fittedContentHeight(menuBody.implicitHeight)

    ServicesMenu {
      id: menuBody
      anchors.fill: parent
      module: root
    }
  }

}
