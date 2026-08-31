pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "BatteryService.qml" as B

QtObject {
    id: brightnessService

    property double brightnessPct: 0

    function adjust(up) {
        brightnessAdjust.command = ["brightnessctl", "set", up ? "5%+" : "5%-"];
        brightnessAdjust.running = true;
    }

    function set(pct) {
        brightnessAdjust.command = ["brightnessctl", "set", Math.max(0, Math.min(100, pct)).toFixed(0) + "%"];
        brightnessAdjust.running = true;
    }

    Process {
        id: brightnessStatus
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,\"\",$4); print $4}'"]
        running: B.BatteryService.hasBattery
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
        running: B.BatteryService.hasBattery
        repeat: true
        onTriggered: brightnessStatus.running = true
    }
}