import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: probeRoot

  required property var unitIds

  property var unitStates: []
  property var unitEnabled: []
  property int lanEstab: 0
  property int lanDegradedMarkers: 0
  property int intervalMs: 3000

  function refresh() {
    if (!probe.running) probe.running = true
  }

  Process {
    id: probe

    // Sin `-l`: un shell de login carga el .bashrc entero en cada sondeo.
    command: ["bash", "-c",
      "systemctl --user is-active " + probeRoot.unitIds.join(" ") + " 2>/dev/null; "
      + "echo '::enabled'; systemctl --user is-enabled " + probeRoot.unitIds.join(" ") + " 2>/dev/null; "
      + "echo '::lanconn'; ss -Hun state established 2>/dev/null | grep -c ':4242'; "
      + "echo '::landeg'; journalctl --user -u lan-mouse.service --since '-30 sec' -o cat --no-pager 2>/dev/null | grep -Ec 'emulation is disabled on the target device|did not respond|connection closed'"]

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        var lines = String(text).replace(/\s+$/, "").split("\n")
        var iEnabled = lines.indexOf("::enabled")
        var iLan = lines.indexOf("::lanconn")
        var iDeg = lines.indexOf("::landeg")
        var act = iEnabled >= 0 ? lines.slice(0, iEnabled) : []
        var en = iEnabled >= 0 ? lines.slice(iEnabled + 1, iLan >= 0 ? iLan : lines.length) : []
        var lanPart = iLan >= 0 ? lines.slice(iLan + 1, iDeg >= 0 ? iDeg : lines.length) : []
        var degPart = iDeg >= 0 ? lines.slice(iDeg + 1) : []

        var states = []
        var enabled = []
        for (var i = 0; i < probeRoot.unitIds.length; i++) {
          states.push((act[i] || "").trim())
          enabled.push((en[i] || "").trim())
        }

        probeRoot.unitStates = states
        probeRoot.unitEnabled = enabled
        probeRoot.lanEstab = parseInt((lanPart[0] || "0").trim(), 10) || 0
        probeRoot.lanDegradedMarkers = parseInt((degPart[0] || "0").trim(), 10) || 0
      }
    }
  }

  Timer {
    interval: probeRoot.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: probeRoot.refresh()
  }
}
