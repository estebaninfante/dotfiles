pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: notifyService

    property bool soundOn: true
    property bool voiceOn: false

    function refresh() {
        soundStateRead.running = false;
        soundStateRead.running = true;
        voiceStateRead.running = false;
        voiceStateRead.running = true;
    }

    function writeFile(name, val) {
        soundStateWrite.command = ["bash", "-c", "mkdir -p \"$HOME/.local/state/opencode\" && printf '" + val + "' > \"$HOME/.local/state/opencode/" + name + "\""];
        soundStateWrite.running = false;
        soundStateWrite.running = true;
    }

    function fmtBool(b) { return b ? "1" : "0"; }

    Process {
        id: soundStateRead
        command: ["bash", "-c", "cat \"$HOME/.local/state/opencode/notify-sound-enabled\" 2>/dev/null || echo 1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: notifyService.soundOn = this.text.trim() !== "0"
        }
    }
    Process {
        id: voiceStateRead
        command: ["bash", "-c", "cat \"$HOME/.local/state/opencode/notify-voice-enabled\" 2>/dev/null || echo 0"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: notifyService.voiceOn = this.text.trim() === "1"
        }
    }
    Process { id: soundStateWrite; command: ["true"]; running: false }
}