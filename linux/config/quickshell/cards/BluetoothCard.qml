import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: bluetoothCard
    width: parent.width
    height: btDetailsOpen ? 70 + btDetails.implicitHeight + 12 : 70
    radius: 12
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.activeSection === "conexiones"

    readonly property bool btScanning: btScan.running

    property bool btOn: false
    property string stateText: "No disponible"
    property bool btDetailsOpen: false
    property string btMessage: ""
    property string selectedMac: ""
    property var btDevices: ListModel {}

    function refreshDevices() {
        btMessage = "Buscando dispositivos...";
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

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        height: 58
        spacing: 10

        Text {
            text: "\uf294"
            color: bluetoothCard.btOn ? "white" : "#555"
            font.family: Theme.fontFamily
            font.pixelSize: 24
            Layout.preferredWidth: 28
        }

        Column {
            spacing: 2

            Text {
                text: "BLUETOOTH"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1.5
            }

            Text {
                text: bluetoothCard.stateText
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 17
                elide: Text.ElideRight
                width: 245
                MouseArea {
                    anchors.fill: parent
                    onClicked: bluetoothCard.btDetailsOpen = !bluetoothCard.btDetailsOpen
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Rectangle {
            width: 48
            height: 30
            radius: 9
            color: btToggleArea.containsMouse ? "white" : "#141414"

            Text {
                anchors.centerIn: parent
                text: bluetoothCard.btOn ? "ON" : "OFF"
                color: btToggleArea.containsMouse ? "#000000" : "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
            }

            MouseArea {
                id: btToggleArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    bluetoothToggle.running = false;
                    bluetoothToggle.running = true;
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: parent.height - 78
        anchors.rightMargin: 62
        z: 1
        onClicked: bluetoothCard.btDetailsOpen = !bluetoothCard.btDetailsOpen
    }

    Column {
        id: btDetails
        anchors.top: parent.top
        anchors.topMargin: 84
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 9
        visible: bluetoothCard.btDetailsOpen
        opacity: bluetoothCard.btDetailsOpen ? 1 : 0

        Rectangle {
            width: parent.width
            height: 34
            radius: 8
            color: btRefreshArea.containsMouse ? "white" : "#141414"
            Text {
                anchors.centerIn: parent
                text: "ESCANEAR BLUETOOTH"
                color: btRefreshArea.containsMouse ? "#000000" : "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.bold: true
            }
            MouseArea {
                id: btRefreshArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: bluetoothCard.refreshDevices()
            }
        }

        ListView {
            width: parent.width
            height: Math.min(contentHeight, 190)
            visible: count > 0
            clip: true
            model: bluetoothCard.btDevices
            spacing: 3
            delegate: Rectangle {
                required property string mac
                required property string name
                width: btDetails.width
                height: 54
                radius: 7
                color: btDeviceArea.containsMouse ? "#1d1d26" : "#141414"
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: name
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: btDetails.width - 16
                    }
                    Text {
                        text: mac
                        color: "#aaa"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }
                MouseArea {
                    id: btDeviceArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        bluetoothCard.selectedMac = mac;
                        bluetoothCard.btMessage = name + " seleccionado";
                    }
                }
            }
        }

        RowLayout {
            width: parent.width
            spacing: 4
            Repeater {
                model: ["PAIR", "TRUST", "CONNECT", "DISCONNECT", "FORGET"]
                delegate: Rectangle {
                    required property string modelData
                    Layout.fillWidth: true
                    height: 34
                    radius: 8
                    color: btActionArea.containsMouse ? "white" : "#141414"
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: btActionArea.containsMouse ? "#000000" : "#aaa"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.bold: true
                    }
                    MouseArea {
                        id: btActionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!bluetoothCard.selectedMac)
                                return;
                            bluetoothAction.routeAudio = modelData === "CONNECT";
                            bluetoothAction.command = bluetoothAction.routeAudio ? ["bash", "-c", "bluetoothctl connect \"" + bluetoothCard.selectedMac + "\" && sleep 1"] : ["bluetoothctl", modelData === "FORGET" ? "remove" : modelData.toLowerCase(), bluetoothCard.selectedMac];
                            bluetoothCard.btMessage = modelData.toLowerCase() + "...";
                            bluetoothAction.running = false;
                            bluetoothAction.running = true;
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: bluetoothCard.btDevices.count ? bluetoothCard.btMessage : (bluetoothCard.btMessage || "Buscando dispositivos...")
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            visible: text !== ""
        }
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
            onRead: line => bluetoothCard.parseDevice(line)
        }
        onExited: bluetoothCard.btMessage = bluetoothCard.btDevices.count ? "Selecciona un dispositivo" : "bluetoothctl no disponible o sin dispositivos"
    }

    Process {
        id: bluetoothAction
        command: ["bluetoothctl", "connect", ""]
        running: false
        property bool routeAudio: false
        onExited: {
            if (routeAudio && exitCode === 0) {
                bluetoothAudioRoute.command = ["bash", "-c", "mac=\"" + bluetoothCard.selectedMac + "\"; sink=$(wpctl status | awk '/Sinks:/{s=1; next} /Sources:/{s=0} s && /[0-9]+\\./{match($0, /[0-9]+\\./); print substr($0, RSTART, RLENGTH - 1)}' | while read id; do wpctl inspect \"$id\" | awk -v mac=\"$mac\" -v sink_id=\"$id\" '$0 ~ mac{found=1} END{if(found) print sink_id}'; done | head -n1); [ -n \"$sink\" ] && wpctl set-default \"$sink\""];
                bluetoothAudioRoute.running = false;
                bluetoothAudioRoute.running = true;
            } else {
                bluetoothCard.btMessage = exitCode === 0 ? "Acción completada" : "Acción fallida";
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
            bluetoothCard.btMessage = exitCode === 0 ? "Audio conectado" : "Audio no disponible";
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
                bluetoothCard.btOn = powered;
                bluetoothCard.stateText = powered ? (parts[1] || "Activado") : "Desactivado";
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
        running: true
        repeat: true
        onTriggered: {
            bluetoothStatus.running = true;
            if (UIState.activeSection === "conexiones" && bluetoothCard.btOn && !btScan.running)
                bluetoothCard.refreshDevices();
        }
    }
}