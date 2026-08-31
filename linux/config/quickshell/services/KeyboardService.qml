pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: keyboardService

    property int kbIndex: 0
    readonly property var kbLabels: ["DV", "ES", "US"]

    function cycleLayout() {
        const next = (keyboardService.kbIndex + 1) % keyboardService.kbLabels.length;
        kbSwitch.command = ["bash", "-c", "for k in $(hyprctl devices -j | jq -r '.keyboards[].name'); do hyprctl switchxkblayout \"$k\" " + next + " >/dev/null 2>&1; done"];
        kbSwitch.running = false;
        kbSwitch.running = true;
    }

    Process {
        id: kbStatus
        command: ["bash", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .active_keymap'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.trim();
                if (!m)
                    return;
                keyboardService.kbIndex = /dvorak|programador/i.test(m) ? 0 : /spanish|espa\u00f1ol/i.test(m) ? 1 : 2;
            }
        }
    }

    Process {
        id: kbSwitch
        command: ["true"]
        running: false
        onExited: {
            kbStatus.running = false;
            kbStatus.running = true;
        }
    }
}