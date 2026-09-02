pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: clockService

    property string clockText: ""
    property string clockFull: ""
    property string countdownText: ""

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

    Process {
        id: runCountdown
        command: ["bash", "-c", "now=$(date +%s); target=$(date -d '2027-01-25 00:00:00' +%s); diff=$((target - now)); if [ $diff -le 0 ]; then echo '🎉'; else days=$((diff / 86400)); hours=$(( (diff % 86400) / 3600 )); echo \"${days}d ${hours}h\"; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: clockService.countdownText = this.text.trim()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: { runDate.running = true; runDateFull.running = true; runCountdown.running = true; }
    }
}