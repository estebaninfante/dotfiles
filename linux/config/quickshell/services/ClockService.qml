pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: clockService

    property string clockText: ""
    property string clockFull: ""

    Process {
        id: runDate
        command: ["date", "+%d %b · %H:%M"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: clockService.clockText = this.text.trim()
        }
    }

    Process {
        id: runDateFull
        command: ["date", "+%A %d de %B %Y %H:%M:%S %Z"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: clockService.clockFull = this.text.trim()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: { runDate.running = true; runDateFull.running = true; }
    }
}