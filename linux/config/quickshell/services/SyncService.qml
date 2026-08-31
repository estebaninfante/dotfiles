pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: syncService

    property bool syncActive: false

    function toggle(turnOn) {
        syncToggle.command = ["bash", "-c",
            turnOn ? "rm -f /tmp/syncthing-manual-off; sudo systemctl start syncthing.service"
                   : "touch /tmp/syncthing-manual-off; sudo systemctl stop syncthing.service"];
        syncToggle.running = false;
        syncToggle.running = true;
    }

    Process {
        id: syncStatus
        command: ["systemctl", "is-active", "syncthing.service"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: syncService.syncActive = this.text.trim() === "active"
        }
    }

    Process {
        id: syncToggle
        command: ["true"]
        running: false
        onExited: syncStatus.running = true
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: syncStatus.running = true
    }
}