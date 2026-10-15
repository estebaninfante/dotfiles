import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: state

  property int pollSeconds: 4

  property var clients: []
  property var monitors: []
  property string localIp: ""
  property string configRaw: ""
  property bool listFailed: false
  property bool daemonOk: false
  property string daemonError: ""
  property string lastError: ""
  property bool busy: false
  property string previewPosition: ""
  property var pendingAction: null

  readonly property bool hasClients: clients.length > 0
  readonly property var primary: hasClients ? clients[0] : null
  readonly property string primaryId: primary ? String(primary.id) : ""
  readonly property string primaryHost: primary ? String(primary.host) : ""
  readonly property string primaryPort: primary ? String(primary.port || "") : ""
  readonly property string primaryEndpoint: primaryPort !== ""
    ? primaryHost + ":" + primaryPort : primaryHost
  readonly property string primaryPosition: primary ? String(primary.position || "") : ""
  readonly property bool primaryActive: primary ? primary.active === true : false
  readonly property string effectivePosition: previewPosition !== ""
    ? previewPosition : primaryPosition

  function refresh() {
    if (busy) return
    listProc.running = false
    listProc.running = true
  }

  function refreshMonitors() {
    monitorsProc.running = false
    monitorsProc.running = true
  }

  function applyList(raw) {
    var parsed = Model.parseList(raw)
    previewPosition = ""
    if (parsed.clients.length === 0) return
    clients = parsed.clients
    daemonError = ""
    lastError = ""
  }

  function applyDaemonFailure(raw) {
    var message = String(raw || "").trim()
    if (message === "") return
    var lines = message.split("\n")
    daemonError = lines[lines.length - 1]
  }

  function applyConfigFallback() {
    if (hasClients || !listFailed || configRaw === "") return
    var parsed = Model.parseConfigClients(configRaw)
    if (parsed.length > 0) clients = parsed
  }

  function setPosition(position) {
    if (!hasClients || !Model.isKnownPosition(position)) return
    if (position === effectivePosition) return
    previewPosition = String(position)
    lastError = ""
    enqueue({ kind: "position", id: primaryId, value: String(position) })
  }

  function setActive(active) {
    if (!hasClients) return
    enqueue({ kind: "active", id: primaryId, value: active === true })
  }

  function enqueue(action) {
    pendingAction = action
    if (!busy) drain()
  }

  function drain() {
    var action = pendingAction
    pendingAction = null
    if (!action) {
      busy = false
      refresh()
      return
    }
    busy = true
    setProc.command = action.kind === "position"
      ? Model.setPositionArgs(action.id, action.value)
      : Model.setActiveArgs(action.id, action.value)
    setProc.running = false
    setProc.running = true
  }

  Process {
    id: listProc
    command: ["lan-mouse", "cli", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: state.applyList(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: state.applyDaemonFailure(text)
    }
    onExited: function(exitCode) {
      state.daemonOk = exitCode === 0
      state.listFailed = exitCode !== 0
      if (exitCode === 0) {
        state.daemonError = ""
        return
      }
      state.clients = []
      state.previewPosition = ""
      state.applyConfigFallback()
      if (state.daemonError === "") state.daemonError = "Daemon lan-mouse no responde"
    }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: state.monitors = Model.parseMonitors(text)
    }
  }

  Process {
    id: ipProc
    command: ["ip", "-j", "-4", "addr", "show", "scope", "global"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: state.localIp = Model.firstLocalIp(text)
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") state.lastError = message.split("\n").pop()
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        saveProc.command = Model.saveConfigArgs()
        saveProc.running = false
        saveProc.running = true
        return
      }
      state.drain()
    }
  }

  Process {
    id: saveProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: state.drain()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/lan-mouse/config.toml"
    watchChanges: true
    printErrors: false
    onLoaded: {
      state.configRaw = text()
      state.applyConfigFallback()
    }
    onLoadFailed: state.configRaw = ""
    onFileChanged: reload()
  }

  Timer {
    interval: Math.max(1, state.pollSeconds) * 1000
    running: true
    repeat: true
    onTriggered: state.refresh()
  }

  Component.onCompleted: {
    refresh()
    refreshMonitors()
    ipProc.running = true
  }
}
