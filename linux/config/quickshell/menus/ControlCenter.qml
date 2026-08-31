import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../config"

PopupWindow {
    id: controlCenter
    implicitWidth: 200
    implicitHeight: ccCol.implicitHeight + 32
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.controlCenterOpen
    property bool syncActive: false
    readonly property var kbLabels: ["DV", "ES", "US"]
    property int kbIndex: 0
    property bool gameArmed: false
    property bool gameModeActive: false

    function gameEnter() {
        gameModeActive = true;
    }
    function gameCancel() {
        gameModeActive = false;
    }
    function gameExit() {
        gameArmed = false;
        gameCancel();
    }

    anchor { window: root; rect.x: root.width - controlCenter.implicitWidth - 12; rect.y: root.height + 8 }
    onOpenedChanged: if (!opened) UIState.hoversReset()
    onVisibleChanged: { if (!visible && UIState.controlCenterOpen) UIState.controlCenterOpen = false; }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 14
        color: "#000000"
        border.color: "#333"
        border.width: 1

        Column {
            id: ccCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            Text { text: "CONTROL"; color: "white"; font.family: fontFamily; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2 }

            Rectangle {
                width: parent.width; height: 30; radius: 8
                color: syncCcArea.containsMouse ? "#1d1d26" : "#141414"
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; spacing: 8
                    Text { text: syncActive ? "\uf0c1" : "\uf127"; color: syncActive ? "white" : "#555"; font.family: fontFamily; font.pixelSize: 13 }
                    Text { text: "Syncthing"; color: syncActive ? "white" : "#aaa"; font.family: fontFamily; font.pixelSize: 11 }
                }
                MouseArea { id: syncCcArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        const stop = syncActive;
                        syncToggle.command = ["bash", "-c",
                            stop ? "touch /tmp/syncthing-manual-off; sudo systemctl stop syncthing.service"
                                 : "rm -f /tmp/syncthing-manual-off; sudo systemctl start syncthing.service"];
                        syncToggle.running = false; syncToggle.running = true;
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 30; radius: 8
                color: kbdCcArea.containsMouse ? "#1d1d26" : "#141414"
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; spacing: 8
                    Text { text: "\uf11c"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 13 }
                    Text { text: kbLabels[kbIndex]; color: "#aaa"; font.family: fontFamily; font.pixelSize: 11; font.bold: true }
                }
                MouseArea { id: kbdCcArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        const next = (kbIndex + 1) % kbLabels.length;
                        kbSwitch.command = ["bash", "-c", "for k in $(hyprctl devices -j | jq -r '.keyboards[].name'); do hyprctl switchxkblayout \"$k\" " + next + " >/dev/null 2>&1; done"];
                        kbSwitch.running = false; kbSwitch.running = true;
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 30; radius: 8
                color: powerCcArea.containsMouse ? "#1d1d26" : "#141414"
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; spacing: 8
                    Text { text: "\uf011"; color: "white"; font.family: fontFamily; font.pixelSize: 13 }
                    Text { text: "Energia"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 11 }
                }
                MouseArea { id: powerCcArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: { UIState.controlCenterOpen = false; UIState.powerMenuOpen = true; }
                }
            }

            Rectangle {
                width: parent.width; height: 30; radius: 8
                color: gameCcArea.containsMouse ? "#1d1d26" : "#141414"
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; spacing: 8
                    Text { text: "\uf11b"; color: gameArmed || gameModeActive ? "white" : "#aaa"; font.family: fontFamily; font.pixelSize: 13 }
                    Text { text: gameArmed ? "Jugando" : gameModeActive ? "Modo juego" : "Modo juegos"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 11 }
                }
                MouseArea { id: gameCcArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        UIState.controlCenterOpen = false;
                        if (gameArmed) gameExit();
                        else if (gameModeActive) gameCancel();
                        else gameEnter();
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#333" }

            Rectangle {
                width: parent.width; height: 30; radius: 8
                color: dashCcArea.containsMouse ? "#1d1d26" : "#141414"
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; spacing: 8
                    Text { text: "\uf009"; color: "white"; font.family: fontFamily; font.pixelSize: 13 }
                    Text { text: "Dashboard"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 11 }
                }
                MouseArea { id: dashCcArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: { UIState.controlCenterOpen = false; UIState.widgetMenuOpen = true; }
                }
            }
        }
    }

    Process {
        id: syncStatus
        command: ["systemctl", "is-active", "syncthing.service"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: syncActive = this.text.trim() === "active"
        }
    }

    Process {
        id: syncToggle
        command: ["true"]
        running: false
        onExited: syncStatus.running = true
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
                kbIndex = /dvorak|programador/i.test(m) ? 0 : /spanish|espa\u00f1ol/i.test(m) ? 1 : 2;
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
