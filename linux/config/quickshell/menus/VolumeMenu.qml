import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

PopupWindow {
    id: volumeMenu
    implicitWidth: 236
    implicitHeight: Math.max(132, volCol.implicitHeight + 26)
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.volumeMenuOpen
    property bool wallpaperMuted: false
    property bool wallpaperFound: false
    property string wallpaperSinkId: ""
    property double volumePct: 0
    property bool volumeMuted: false

    anchor { window: root; rect.x: root.width - volumeMenu.implicitWidth - 72; rect.y: root.height + 8 }
    onOpenedChanged: {
        if (opened) {
            AudioService.scanAudioDevices();
            wallAudioStatus.running = true;
        } else {
            UIState.hoversReset();
        }
    }
    onVisibleChanged: { if (!visible && UIState.volumeMenuOpen) UIState.volumeMenuOpen = false; }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 12
        color: "#000000"
        border.color: "#333"
        border.width: 1
        Column {
            id: volCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            RowLayout {
                width: parent.width
                Text { text: "VOLUMEN"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.5 }
                Item { Layout.fillWidth: true }
                Text { text: volumeMuted ? "silenciado" : Math.round(volumePct) + "%"; color: "white"; font.family: fontFamily; font.pixelSize: 10 }
            }
            Row {
                width: parent.width
                spacing: 6
                Rectangle {
                    width: parent.width - 54
                    height: 26
                    radius: 8
                    color: "#000000"
                    border.color: "#333"
                    Rectangle { width: parent.width * Math.min(volumePct, 100) / 100; height: parent.height; radius: 8; color: "white" }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => { volumeAdjust.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.max(0, Math.min(100, mouse.x / width * 100)).toFixed(0) + "%" ]; volumeAdjust.running = true; }
                    }
                }
                TextInput {
                    id: volumeInput
                    width: 48
                    height: 26
                    text: Math.round(volumePct).toString()
                    color: "white"
                    font.family: fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    onAccepted: { volumeAdjust.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.max(0, Math.min(100, parseFloat(text) || 0)).toFixed(0) + "%" ]; volumeAdjust.running = true; focus = false; }
                    Rectangle { anchors.fill: parent; z: -1; radius: 7; color: "#000000"; border.color: "#333" }
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#333" }

            Row {
                width: parent.width
                spacing: 6
                visible: wallpaperFound

                Text {
                    width: parent.width - 54
                    height: 26
                    verticalAlignment: Text.AlignVCenter
                    text: "\uf001  Audio del wallpaper"
                    color: "white"
                    font.family: fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: 48
                    height: 26
                    radius: 7
                    color: wallAudioToggleArea.containsMouse ? "white" : wallpaperMuted ? "#141414" : "#141414"
                    border.color: "#333"

                    Text {
                        anchors.centerIn: parent
                        text: wallpaperMuted ? "OFF" : "ON"
                        color: wallAudioToggleArea.containsMouse ? "#000000" : wallpaperMuted ? "#aaa" : "white"
                        font.family: fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        id: wallAudioToggleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!wallpaperSinkId)
                                return;
                            wallAudioToggle.command = ["wpctl", "set-mute", wallpaperSinkId, wallpaperMuted ? "0" : "1"];
                            wallAudioToggle.running = false;
                            wallAudioToggle.running = true;
                        }
                    }
                }
            }

            Text {
                text: "SALIDAS"
                color: "#aaa"
                font.family: fontFamily
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 1.5
                visible: AudioService.audioSinks.count > 0
            }

            Repeater {
                model: AudioService.audioSinks

                delegate: Rectangle {
                    required property string deviceId
                    required property string name
                    required property bool selected
                    width: parent.width
                    height: 22
                    radius: 6
                    color: volSinkArea.containsMouse ? "#1d1d26" : selected ? "#1d1d26" : "#141414"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: (selected ? "●  " : "○  ") + name
                        color: selected ? "white" : "white"
                        font.family: fontFamily
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: volSinkArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: AudioService.setDefaultDevice(deviceId)
                    }
                }
            }

            Text {
                text: "ENTRADAS"
                color: "#aaa"
                font.family: fontFamily
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 1.5
                visible: AudioService.audioSources.count > 0
            }

            Repeater {
                model: AudioService.audioSources

                delegate: Rectangle {
                    required property string deviceId
                    required property string name
                    required property bool selected
                    width: parent.width
                    height: 22
                    radius: 6
                    color: volSourceArea.containsMouse ? "#1d1d26" : selected ? "#1d1d26" : "#141414"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: (selected ? "●  " : "○  ") + name
                        color: selected ? "white" : "white"
                        font.family: fontFamily
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: volSourceArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: AudioService.setDefaultDevice(deviceId)
                    }
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
                volumePct = parseFloat(p[0]) || 0;
                volumeMuted = p[1] === "yes";
                if (!volumeInput.activeFocus)
                    volumeInput.text = Math.round(volumePct).toString();
            }
        }
    }

    Process { id: volumeAdjust; command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"]; running: false; onExited: volumeStatus.running = true }

    Process {
        id: wallAudioStatus
        command: ["bash", "-c", "id=$(wpctl status | sed -n '/^Audio$/,/^Video$/p' | grep -i wallpaper | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\.$/) {gsub(/\\./,\"\",$i); print $i; exit}}'); [ -n \"$id\" ] && { printf '%s|' \"$id\"; wpctl get-volume \"$id\"; }"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                const bar = t.indexOf("|");
                wallpaperFound = bar > 0;
                wallpaperSinkId = bar > 0 ? t.slice(0, bar) : "";
                wallpaperMuted = /MUTED/.test(t);
            }
        }
    }

    Process {
        id: wallAudioToggle
        command: ["true"]
        running: false
        onExited: wallAudioStatus.running = true
    }
}
