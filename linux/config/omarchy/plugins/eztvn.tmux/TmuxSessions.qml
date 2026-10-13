import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property int refreshMs: 5000
  property bool panelOpen: false
  property var sessions: []
  property bool loaded: false
  property int exitCode: -1
  property int killExitCode: 0
  property real nowSec: 0
  property bool refreshQueued: false

  readonly property int count: sessions.length
  readonly property bool missing: exitCode === 127
  readonly property bool empty: sessions.length === 0
  readonly property bool killing: killProc.running

  function refresh() {
    if (list.running) {
      root.refreshQueued = true
      return
    }
    root.refreshQueued = false
    list.running = true
  }

  function flushQueuedRefresh() {
    if (!root.refreshQueued) return
    root.refreshQueued = false
    Qt.callLater(root.refresh)
  }

  function stampNow() {
    root.nowSec = Date.now() / 1000
  }

  function applySessions(text) {
    var next = Model.parseSessions(text)
    root.loaded = true
    root.stampNow()
    if (!Model.sameSessions(root.sessions, next)) root.sessions = next
  }

  function applyExit(code) {
    root.exitCode = code
    root.loaded = true
    root.stampNow()
    if (code !== 0 && root.sessions.length > 0) root.sessions = []
    root.flushQueuedRefresh()
  }

  function killSession(name) {
    return root.runKill(Model.killSessionArgv(name))
  }

  function killAllSessions() {
    return root.runKill(Model.killServerArgv())
  }

  function runKill(argv) {
    if (root.killing || argv.length === 0) return false
    root.killExitCode = 0
    killProc.cmd = argv
    killProc.running = true
    return true
  }

  Timer {
    interval: Math.max(1000, root.refreshMs)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: list
    command: ["tmux", "list-sessions", "-F", Model.sessionFormat]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySessions(this.text)
    }

    stderr: StdioCollector {
      waitForEnd: true
    }

    onExited: function(code) { root.applyExit(code) }
  }

  Process {
    id: killProc
    property var cmd: []
    command: cmd

    stdout: StdioCollector {
      waitForEnd: true
    }

    stderr: StdioCollector {
      waitForEnd: true
    }

    onExited: function(code) {
      root.killExitCode = code
      root.refresh()
    }
  }
}
