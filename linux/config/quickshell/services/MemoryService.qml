pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: memoryService

    property double pct: NaN
    property string label: "--%"

    Process {
        id: runMem
        command: ["bash", "-c", "free -m | awk '/Mem:/{printf \"%.0f\", ($2-$7)/$2*100}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                memoryService.pct = parseFloat(this.text);
                memoryService.label = memoryService.pct + "%";
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: runMem.running = true
    }
}