import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: audioCard
    width: parent.width
    height: audioDetailsOpen ? audioDetails.y + audioDetails.implicitHeight + 12 : 70
    radius: 12
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.activeSection === "dispositivos"

    property bool audioDetailsOpen: true
    property var cameras: ListModel {}

    function refreshCameras() {
        cameras.clear();
        cameraStatus.running = false;
        cameraStatus.running = true;
    }

    function parseCamera(line) {
        const parts = line.split("|");
        if (parts.length < 2)
            return;
        cameras.append({ device: parts[0], name: parts[1] || parts[0] });
    }

    function selectDevice(id, label) {
        AudioService.message = "Seleccionando " + label + "...";
        AudioService.setDefaultDevice(id);
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
            text: "\uf028"
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 24
            Layout.preferredWidth: 28
        }

        Column {
            spacing: 2
            Layout.fillWidth: true
            Text {
                text: "DISPOSITIVOS"
                color: "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.letterSpacing: 1.5
            }
            Text {
                text: AudioService.audioSinks.count + " salidas · " + AudioService.audioSources.count + " entradas · " + audioCard.cameras.count + " cámaras"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 14
            }
        }

        Text {
            text: "\uf078"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: audioCard.audioDetailsOpen = !audioCard.audioDetailsOpen
    }

    Column {
        id: audioDetails
        anchors.top: parent.top
        anchors.topMargin: 70
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 8
        visible: audioCard.audioDetailsOpen

        Text {
            text: "CÁMARAS"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: true
            visible: audioCard.cameras.count > 0
        }

        Repeater {
            model: audioCard.cameras
            delegate: Rectangle {
                required property string device
                required property string name
                width: audioDetails.width
                height: 34
                radius: 8
                color: "#000000"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "●  " + name + " (" + device + ")"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            text: "SALIDAS"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: true
            visible: AudioService.audioSinks.count > 0
        }

        Repeater {
            model: AudioService.audioSinks
            delegate: Rectangle {
                required property string deviceId
                required property string name
                required property bool selected
                width: audioDetails.width
                height: 34
                radius: 8
                color: audioDeviceArea.containsMouse ? "#1d1d26" : selected ? "#1d1d26" : "#141414"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (selected ? "●  " : "○  ") + name
                    color: selected ? "white" : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: audioDeviceArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: audioCard.selectDevice(deviceId, name)
                }
            }
        }

        Text {
            text: "ENTRADAS"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: true
            visible: AudioService.audioSources.count > 0
        }

        Repeater {
            model: AudioService.audioSources
            delegate: Rectangle {
                required property string deviceId
                required property string name
                required property bool selected
                width: audioDetails.width
                height: 34
                radius: 8
                color: audioInputArea.containsMouse ? "#1d1d26" : selected ? "#1d1d26" : "#141414"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (selected ? "●  " : "○  ") + name
                    color: selected ? "white" : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: audioInputArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: audioCard.selectDevice(deviceId, name)
                }
            }
        }

        Text {
            text: AudioService.message || "Selecciona dispositivo predeterminado"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    Process {
        id: cameraStatus
        command: ["bash", "-c", "for d in /dev/video*; do [ -e \"$d\" ] || continue; name=$(udevadm info -q property -n \"$d\" 2>/dev/null | awk -F= '/^ID_V4L_PRODUCT=/{print $2; exit}'); printf '%s|%s\\n' \"$d\" \"${name:-$d}\"; done"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => audioCard.parseCamera(line)
        }
    }
}