import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: notifCard
    width: parent.width
    implicitHeight: columnContent.implicitHeight + 24
    radius: 12
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.activeSection === "notificaciones"

    onVisibleChanged: if (visible) NotifyService.refresh()

    Column {
        id: columnContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        spacing: 10

        RowLayout {
            width: parent.width

            Text {
                text: "\uf0f3"
                color: NotifyService.soundOn ? "white" : "#aaa"
                font.family: Theme.fontFamily
                font.pixelSize: 22
                Layout.preferredWidth: 28
            }

            Column {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: "SONIDO"
                    color: "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }

                Text {
                    text: NotifyService.soundOn ? "Sonido activado" : "Sonido silenciado"
                    color: NotifyService.soundOn ? "white" : "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }
            }

            Rectangle {
                width: 48
                height: 30
                radius: 9
                color: soundToggleArea.containsMouse ? "white" : NotifyService.soundOn ? "#141414" : "#141414"
                border.color: NotifyService.soundOn ? "white" : "#333"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: NotifyService.soundOn ? "ON" : "OFF"
                    color: soundToggleArea.containsMouse ? "#000000" : NotifyService.soundOn ? "white" : "#555"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                }

                MouseArea {
                    id: soundToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        const next = !NotifyService.soundOn;
                        NotifyService.soundOn = next;
                        NotifyService.writeFile("notify-sound-enabled", NotifyService.fmtBool(next));
                    }
                }
            }
        }

        RowLayout {
            width: parent.width

            Text {
                text: "\uf130"
                color: NotifyService.voiceOn ? "white" : "#888"
                font.family: Theme.fontFamily
                font.pixelSize: 20
                Layout.preferredWidth: 28
            }

            Column {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: "VOZ DEL RESUMEN"
                    color: "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }

                Text {
                    text: NotifyService.voiceOn ? "Habla el resumen al terminar" : "Voz desactivada"
                    color: NotifyService.voiceOn ? "white" : "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }
            }

            Rectangle {
                width: 48
                height: 30
                radius: 9
                color: voiceToggleArea.containsMouse ? "white" : NotifyService.voiceOn ? "#141414" : "#141414"
                border.color: NotifyService.voiceOn ? "white" : "#333"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: NotifyService.voiceOn ? "ON" : "OFF"
                    color: voiceToggleArea.containsMouse ? "#000000" : NotifyService.voiceOn ? "white" : "#555"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                }

                MouseArea {
                    id: voiceToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        const next = !NotifyService.voiceOn;
                        NotifyService.voiceOn = next;
                        NotifyService.writeFile("notify-voice-enabled", NotifyService.fmtBool(next));
                    }
                }
            }
        }

        RowLayout {
            width: parent.width
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: 8
                color: soundTestArea.containsMouse ? "#222" : "#000000"

                Text {
                    anchors.centerIn: parent
                    text: "\uf028  Probar sonido"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                }

                MouseArea {
                    id: soundTestArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        soundTest.command = ["bash", "-c", "pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga"];
                        soundTest.running = false;
                        soundTest.running = true;
                    }
                }
            }
        }
    }

    Process { id: soundTest; command: ["true"]; running: false }
}