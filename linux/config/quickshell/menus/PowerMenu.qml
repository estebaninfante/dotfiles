import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"

PopupWindow {
    id: powerMenu
    implicitWidth: 280
    implicitHeight: powerCol.implicitHeight + 32
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.powerMenuOpen
    property string pendingAction: ""
    readonly property bool powerProfilesOpen: UIState.powerMenuProfilesOpen
    property string powerProfile: ""

    onOpenedChanged: {
        if (!opened) {
            UIState.powerMenuProfilesOpen = false;
            UIState.hoversReset();
        } else {
            pendingAction = "";
            powerProfileStatus.running = true;
        }
    }
    onVisibleChanged: { if (!visible) opened = false; }

    anchor {
        window: root
        rect.x: root.width - powerMenu.implicitWidth - 12
        rect.y: root.height + 8
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 14
        color: "#000000"
        border.color: "#333"
        border.width: 1
    }

    Column {
        id: powerCol
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Text {
            text: "ENERGÍA"
            color: "#aaa"
            font.family: fontFamily
            font.pixelSize: 10
            font.letterSpacing: 3
            font.bold: true
        }

        Text {
            width: parent.width
            text: pendingAction ? "¿Confirmar: " + pendingAction + "?" : "Selecciona una acción"
            color: "white"
            font.family: fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Rectangle {
            width: parent.width
            height: 34
            radius: 8
            color: profileHeaderArea.containsMouse || powerProfilesOpen ? "#1d1d26" : "#141414"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                Text {
                    text: "\uf0e7"
                    color: "white"
                    font.family: fontFamily
                    font.pixelSize: 13
                }
                Text {
                    text: "PERFIL DE ENERGÍA"
                    color: "#aaa"
                    font.family: fontFamily
                    font.pixelSize: 9
                    font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    text: (powerProfile || "desconocido").toUpperCase() + "  \uf078"
                    color: "#aaa"
                    font.family: fontFamily
                    font.pixelSize: 8
                }
            }

            MouseArea {
                id: profileHeaderArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: UIState.powerMenuProfilesOpen = !UIState.powerMenuProfilesOpen
            }
        }

        Column {
            width: parent.width
            spacing: 4
            visible: powerProfilesOpen

            Repeater {
                model: ["power-saver", "balanced", "performance"]
                delegate: Rectangle {
                    required property string modelData
                    width: parent.width
                    height: 30
                    radius: 7
                    color: profileArea.containsMouse ? "#1d1d26" : powerProfile === modelData ? "#1d1d26" : "#141414"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        Text {
                            text: powerProfile === modelData ? "●" : "○"
                            color: powerProfile === modelData ? "white" : "#555"
                            font.family: fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            text: modelData === "power-saver" ? "AHORRO" : modelData === "balanced" ? "EQUILIBRADO" : "RENDIMIENTO"
                            color: "#aaa"
                            font.family: fontFamily
                            font.pixelSize: 9
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData
                            color: "#555"
                            font.family: fontFamily
                            font.pixelSize: 8
                        }
                    }

                    MouseArea {
                        id: profileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            powerProfileSet.command = ["powerprofilesctl", "set", modelData];
                            powerProfileSet.running = true;
                            UIState.powerMenuProfilesOpen = false;
                        }
                    }
                }
            }
        }

        Repeater {
            model: ["SUSPENDER", "CERRAR SESIÓN", "REINICIAR", "APAGAR"]
            delegate: Rectangle {
                required property string modelData
                width: powerCol.width
                height: 34
                radius: 8
                color: powerActionArea.containsMouse ? (modelData === "APAGAR" ? "#eba0ac" : "white") : "#141414"

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: powerActionArea.containsMouse ? "#000000" : "#aaa"
                    font.family: fontFamily
                    font.pixelSize: 9
                    font.bold: true
                }

                MouseArea {
                    id: powerActionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        pendingAction = modelData;
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 6
            visible: pendingAction !== ""

            Rectangle {
                width: (parent.width - 6) / 2
                height: 34
                radius: 8
                color: cancelPowerArea.containsMouse ? "#222" : "#141414"
                Text {
                    anchors.centerIn: parent
                    text: "CANCELAR"
                    color: "#aaa"
                    font.family: fontFamily
                    font.pixelSize: 9
                    font.bold: true
                }
                MouseArea {
                    id: cancelPowerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: pendingAction = ""
                }
            }

            Rectangle {
                width: (parent.width - 6) / 2
                height: 34
                radius: 8
                color: confirmPowerArea.containsMouse ? "#eba0ac" : "#141414"
                Text {
                    anchors.centerIn: parent
                    text: "CONFIRMAR"
                    color: confirmPowerArea.containsMouse ? "#000000" : "white"
                    font.family: fontFamily
                    font.pixelSize: 9
                    font.bold: true
                }
                MouseArea {
                    id: confirmPowerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        powerAction.command = pendingAction === "SUSPENDER" ? ["systemctl", "suspend"] : pendingAction === "CERRAR SESIÓN" ? ["hyprctl", "dispatch", "exit"] : pendingAction === "REINICIAR" ? ["systemctl", "reboot"] : ["systemctl", "poweroff"];
                        UIState.powerMenuOpen = false;
                        pendingAction = "";
                        powerAction.running = true;
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: "#333"
        }

        Rectangle {
            width: parent.width
            height: 26
            radius: 7
            color: closePowerArea.containsMouse ? "#000000" : "transparent"
            Text {
                anchors.centerIn: parent
                text: "CERRAR MENÚ"
                color: "#888"
                font.family: fontFamily
                font.pixelSize: 9
            }
            MouseArea {
                id: closePowerArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: UIState.powerMenuOpen = false
            }
        }
    }

    Process {
        id: powerProfileStatus
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: powerProfile = this.text.trim()
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

    Process {
        id: powerAction
        command: ["true"]
        running: false
    }
}
