import QtQuick
import Quickshell.Io

// Toggle state and actions. One state probe on a slow timer plus a
// fire-and-refresh action process; the page does no shell work itself.
Item {
  id: root

  property bool active: false
  property var data: ({})

  readonly property string scriptPath: Qt.resolvedUrl("toggles.sh").toString().replace("file://", "")

  function refresh() {
    if (!root.active) return
    if (!stateProc.running) stateProc.running = true
  }

  // args is an argv tail: ["wifi"], ["volume", "up"], ...
  function run(args) {
    if (actionProc.running) return
    var command = ["/bin/bash", root.scriptPath]
    for (var i = 0; i < args.length; i++) command.push(String(args[i]))
    actionProc.command = command
    actionProc.running = true
  }

  function apply(raw) {
    try {
      var parsed = JSON.parse(String(raw).trim())
      if (parsed) root.data = parsed
    } catch (e) {
      // Keep the previous sample; the next tick replaces it.
    }
  }

  Process {
    id: stateProc
    command: ["/bin/bash", root.scriptPath, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Process {
    id: actionProc
    // Some switches (Bluetooth, night light) take a second or two to settle;
    // re-probe only after the action exits so the readout matches reality.
    onExited: root.refresh()
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}