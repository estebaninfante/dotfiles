pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: superKeyService

    property bool superDown: false
    property bool superHeld: false

    onSuperDownChanged: {
        if (superKeyService.superDown) {
            superKeyService.superHeld = false;
            superHoldTimer.restart();
        } else {
            superHoldTimer.stop();
            superKeyService.superHeld = false;
        }
    }

    Timer {
        id: superHoldTimer
        interval: 250
        repeat: false
        onTriggered: superKeyService.superHeld = true
    }

    Process {
        id: superMonitor
        command: ["super-hold-monitor.sh"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data === "1")
                    superKeyService.superDown = true;
                else if (data === "0")
                    superKeyService.superDown = false;
            }
        }
    }
}