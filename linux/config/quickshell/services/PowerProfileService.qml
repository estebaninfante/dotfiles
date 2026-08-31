pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: powerProfileService

    property string powerProfile: ""

    function set(profile) {
        powerProfileSet.command = ["powerprofilesctl", "set", profile];
        powerProfileSet.running = true;
    }

    Process {
        id: powerProfileStatus
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: powerProfileService.powerProfile = this.text.trim()
        }
    }

    Process {
        id: powerProfileSet
        command: ["powerprofilesctl", "set", "balanced"]
        running: false
        onExited: {
            powerProfileStatus.running = false;
            powerProfileStatus.running = true;
        }
    }
}