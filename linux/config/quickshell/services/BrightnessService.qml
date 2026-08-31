pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: brightnessService

    property double brightnessPct: 0

    function adjust(up) {
        brightnessAdjust.command = ["brightnessctl", "set", up ? "5%+" : "5%-"];
        brightnessAdjust.running = true;
    }

    Process {
        id: brightnessStatus
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,\"\",$4); print $4}'"]
        running: BatteryService.hasBattery
        stdout: StdioCollector {
            onStreamFinished: brightnessService.brightnessPct = parseFloat(this.text.trim()) || 0
        }
    }

    Process {
        id: brightnessAdjust
        command: ["brightnessctl", "set", "5%+"]
        running: false
        onExited: brightnessStatus.running = true
    }

    Timer {
        interval: 3000
        running: BatteryService.hasBattery
        repeat: true
        onTriggered: brightnessStatus.running = true
    }
}