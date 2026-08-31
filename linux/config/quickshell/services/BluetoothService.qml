pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

QtObject {
    id: bluetoothService

    property bool btOn: false
    property string stateText: "No disponible"
    property bool btDetailsOpen: false
    property string btMessage: ""
    property string selectedMac: ""
    property var btDevices: ListModel {}

    function refreshDevices() {
        bluetoothService.btMessage = "Buscando dispositivos...";
        btDevices.clear();
        btScan.running = false;
        btScan.running = true;
    }

    function parseDevice(line) {
        const match = line.trim().match(/^Device\s+([^ ]+)\s+(.+)$/);
        if (!match)
            return;
        for (let i = 0; i < btDevices.count; i++) {
            if (btDevices.get(i).mac === match[1])
                return;
        }
        btDevices.append({
            mac: match[1],
            name: match[2]
        });
    }

    Process {
        id: btScan
        command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
        running: false
        onExited: {
            btList.running = false;
            btList.running = true;
        }
    }

    Process {
        id: btList
        command: ["bluetoothctl", "devices"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => bluetoothService.parseDevice(line)
        }
        onExited: bluetoothService.btMessage = bluetoothService.btDevices.count ? "Selecciona un dispositivo" : "bluetoothctl no disponible o sin dispositivos"
    }

    Process {
        id: bluetoothAction
        command: ["bluetoothctl", "connect", ""]
        running: false
        property bool routeAudio: false
        onExited: {
            if (routeAudio && exitCode === 0) {
                bluetoothAudioRoute.command = ["bash", "-c", "mac=\"" + bluetoothService.selectedMac + "\"; sink=$(wpctl status | awk '/Sinks:/{s=1; next} /Sources:/{s=0} s && /[0-9]+\\./{match($0, /[0-9]+\\./); print substr($0, RSTART, RLENGTH - 1)}' | while read id; do wpctl inspect \"$id\" | awk -v mac=\"$mac\" -v sink_id=\"$id\" '$0 ~ mac{found=1} END{if(found) print sink_id}'; done | head -n1); [ -n \"$sink\" ] && wpctl set-default \"$sink\""];
                bluetoothAudioRoute.running = false;
                bluetoothAudioRoute.running = true;
            } else {
                bluetoothService.btMessage = exitCode === 0 ? "Acción completada" : "Acción fallida";
                bluetoothStatus.running = false;
                bluetoothStatus.running = true;
            }
        }
    }

    Process {
        id: bluetoothAudioRoute
        command: ["true"]
        running: false
        onExited: {
            bluetoothService.btMessage = exitCode === 0 ? "Audio conectado" : "Audio no disponible";
            bluetoothStatus.running = false;
            bluetoothStatus.running = true;
        }
    }

    Process {
        id: bluetoothStatus
        command: ["bash", "-c", "powered=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'); device=$(bluetoothctl devices Connected 2>/dev/null | awk 'NR==1{sub(/^Device [^ ]+ /,\"\"); print}'); printf '%s|%s' \"$powered\" \"$device\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split("|");
                const powered = parts[0] === "yes";
                bluetoothService.btOn = powered;
                bluetoothService.stateText = powered ? (parts[1] || "Activado") : "Desactivado";
            }
        }
    }

    Process {
        id: bluetoothToggle
        command: ["bash", "-c", "powered=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'); bluetoothctl power $([[ \"$powered\" == \"yes\" ]] && echo off || echo on)"]
        running: false

        onExited: {
            bluetoothStatus.running = false;
            bluetoothStatus.running = true;
        }
    }

    Timer {
        interval: 20000
        running: UIState.widgetMenuOpen && UIState.activeSection === "conexiones"
        repeat: true
        onTriggered: {
            bluetoothStatus.running = true;
            if (bluetoothService.btOn && !btScan.running)
                bluetoothService.refreshDevices();
        }
    }
}