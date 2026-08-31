pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: audioService

    property string message: ""
    property double volumePct: 0
    property bool volumeMuted: false
    property var audioSinks: ListModel {}
    property var audioSources: ListModel {}

    function adjustVolume(up) {
        volumeAdjust.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", up ? "5%+" : "5%-"];
        volumeAdjust.running = true;
    }

    function scanAudioDevices() {
        audioSinks.clear();
        audioSources.clear();
        audioStatus.running = false;
        audioStatus.running = true;
    }

    function setDefaultDevice(id) {
        audioSetDefault.command = ["wpctl", "set-default", id];
        audioSetDefault.running = false;
        audioSetDefault.running = true;
    }

    Process {
        id: audioStatus
        command: ["bash", "-c", "wpctl status | awk '/^Audio$/{audio=1} /^Video$/{audio=0; s=\"\"} /Sinks:/ && audio{s=\"sink\"; next} /Sources:/ && audio{s=\"source\"; next} /Filters:/{s=\"\"; next} audio && s && match($0,/\\*?[[:space:]]*[0-9]+\\./){prefix=substr($0,RSTART,RLENGTH-1); star=(prefix ~ /\\*/ ? \"*\" : \"\"); gsub(/[^0-9]/,\"\",prefix); line=substr($0,RSTART+RLENGTH); sub(/^[[:space:]]+/,\"\",line); print s \"|\" prefix \"|\" line \"|\" star}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                for (const line of lines) {
                    const p = line.split("|");
                    if (p.length < 4)
                        continue;
                    const item = { deviceId: p[1], name: p[2], selected: p[3] === "*" };
                    if (p[0] === "sink")
                        audioService.audioSinks.append(item);
                    else if (p[0] === "source")
                        audioService.audioSources.append(item);
                }
            }
        }
    }

    Process {
        id: volumeStatus
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"%s %s\", $2 * 100, ($3 == \"[MUTED]\" ? \"yes\" : \"no\")}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split(/\s+/);
                audioService.volumePct = parseFloat(p[0]) || 0;
                audioService.volumeMuted = p[1] === "yes";
            }
        }
    }

    Process { id: volumeAdjust; command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"]; running: false; onExited: volumeStatus.running = true }

    Process {
        id: audioSetDefault
        command: ["wpctl", "set-default", "0"]
        running: false
        onExited: {
            audioService.message = exitCode === 0 ? "Dispositivo predeterminado actualizado" : "No se pudo seleccionar dispositivo";
            audioService.scanAudioDevices();
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: volumeStatus.running = true
    }
}