import QtQuick
import Quickshell
import Quickshell.Io

// Reads the notification history the omarchy.notifications service keeps on
// disk. Third-party plugins have no handle on the service's popup model, but
// historyDir is documented user state and is exactly the "what did I miss"
// list this page wants.
//
// Best-effort by design: the service archives entries with mv/rm through its
// own queue, and `clear` here does the same thing with plain rm. Worst case a
// clear races an archive and one entry survives until the next read.
Item {
  id: root

  property bool active: false
  property var entries: []
  property string signature: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/notifications"
  readonly property string historyDir: stateDir + "/history"

  function refresh() {
    if (!root.active) return
    if (!readProc.running) readProc.running = true
  }

  function clear() {
    if (!clearProc.running) clearProc.running = true
  }

  function apply(raw) {
    var lines = String(raw || "").split("\n")
    var list = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      try {
        var entry = JSON.parse(line)
        if (entry && entry.summary !== undefined) list.push(entry)
      } catch (e) {
        // A torn line from a write in flight — skipped, next read catches up.
      }
    }
    list.sort(function(a, b) { return (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0) })

    var nextSignature = ""
    for (var j = 0; j < list.length; j++) nextSignature += String(list[j].timestamp) + ","
    // Reassigning the model on every poll would rebuild every row and reset
    // the scroll position; only a real history change replaces the array.
    if (nextSignature === root.signature) return
    root.signature = nextSignature
    root.entries = list
  }

  Process {
    id: readProc
    command: ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", root.historyDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Process {
    id: clearProc
    command: ["bash", "-c", "rm -f \"$1\"/*.json", "--", root.historyDir]
    onExited: root.refresh()
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}