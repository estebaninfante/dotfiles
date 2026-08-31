pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: memoryService

    property double pct: NaN

    Process {
        id: runMem
        command: ["bash", "-c", "free -m | awk '/Mem:/{printf \"%.0f\", ($2-$7)/$2*100}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: memoryService.pct = parseFloat(this.text)
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: runMem.running = true
    }
}