import QtQuick
import Quickshell.Io

// Non-blocking system probe: runs probe-system.sh on a timer while the page is
// visible and publishes the parsed JSON as `data`. The page does no process
// work of its own, so the sampling policy lives in one place.
Item {
  id: root

  property bool active: false
  property var data: ({})

  readonly property string scriptPath: Qt.resolvedUrl("probe-system.sh").toString().replace("file://", "")

  function refresh() {
    if (!root.active) return
    if (!probe.running) probe.running = true
  }

  function apply(raw) {
    try {
      var parsed = JSON.parse(String(raw).trim())
      if (parsed) root.data = parsed
    } catch (e) {
      // A torn read (process killed mid-write) just leaves the previous
      // sample in place; the next tick replaces it.
    }
  }

  Process {
    id: probe
    command: ["/bin/bash", root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
