pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// Protector visual independiente: pantalla negra cada N minutos durante M segundos.
// Estado y config en ~/.local/state/quickshell/eyecare.conf.
Item {
    id: eyeCareService

    property bool onBreak: false
    property int intervalMin: 20
    property int breakSec: 20
    property int remaining: 0

    readonly property string confPath: "/home/eztvn/.local/state/quickshell/eyecare.conf"

    function fmt(secs) {
        if (secs < 0) secs = 0;
        const m = Math.floor(secs / 60);
        const s = secs % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function setIntervalMin(v) {
        intervalMin = Math.max(5, Math.min(60, v))
        persist()
        if (!onBreak) startInterval()
    }

    function setBreakSec(v) {
        breakSec = Math.max(5, Math.min(60, v))
        persist()
    }

    function startInterval() {
        remaining = intervalMin * 60
        intervalTimer.start()
    }

    function persist() {
        persistProc.running = false
        persistProc.command = ["bash", "-c",
            'mkdir -p "$(dirname ' + confPath + ')" && printf "interval_min=%s\\nbreak_sec=%s\\n" ' +
            intervalMin + " " + breakSec + ' > "' + confPath + '"']
        persistProc.running = true
    }

    function loadConf() {
        loadProc.running = false
        loadProc.running = true
    }

    Timer {
        id: intervalTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (eyeCareService.remaining > 0) {
                eyeCareService.remaining--
            }
            if (eyeCareService.remaining <= 0) {
                intervalTimer.stop()
                eyeCareService.onBreak = true
                eyeCareService.remaining = eyeCareService.breakSec
                breakTimer.start()
            }
        }
    }

    Timer {
        id: breakTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (eyeCareService.remaining > 0) {
                eyeCareService.remaining--
            }
            if (eyeCareService.remaining <= 0) {
                breakTimer.stop()
                eyeCareService.onBreak = false
                eyeCareService.startInterval()
            }
        }
    }

    Process {
        id: loadProc
        command: ["true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n")
                for (const line of lines) {
                    const [k, v] = line.split("=")
                    if (k === "interval_min") eyeCareService.intervalMin = parseInt(v) || 20
                    else if (k === "break_sec") eyeCareService.breakSec = parseInt(v) || 20
                }
                eyeCareService.startInterval()
            }
        }
    }

    Process {
        id: persistProc
        command: ["true"]
        running: false
    }

    Component.onCompleted: loadConf()
}
