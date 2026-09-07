import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

// Pantalla negra fullscreen durante el descanso del pomodoro.
// Pausa hypridle para que hyprlock no se active durante el overlay.
PanelWindow {
    id: pomodoroOverlay
    visible: PomodoroService.state === "break" || PomodoroService.state === "paused_break" || PomodoroService.state === "break_done"
    onVisibleChanged: {
        if (visible) killIdle.running = true;
        else startIdle.running = true;
    }

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "#000000"

    property string activityText: ""

    Column {
        anchors.centerIn: parent
        spacing: 18

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: PomodoroService.state === "break_done" ? "\uf058" : "\uf0f4"
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 64
            SequentialAnimation on opacity {
                loops: PomodoroService.state === "break_done" ? 1 : Animation.Infinite
                NumberAnimation { to: 0.2; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: PomodoroService.state === "break_done" ? "¿CONTINUAR?" : "DESCANSA"
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
            font.letterSpacing: 8
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: PomodoroService.fmt(PomodoroService.remaining)
            visible: PomodoroService.state !== "break_done"
            color: "#aaaaaa"
            font.family: Theme.fontFamily
            font.pixelSize: 48
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: PomodoroService.state === "break_done" ? "Ciclo " + PomodoroService.cycle + " completado" : "Levántate, estira la vista, hidrátate"
            color: "#555555"
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        // Campo de texto para actividad
        Rectangle {
            width: 320
            height: 40
            radius: 8
            color: "#1a1a1a"
            border.color: "#444444"
            border.width: 1
            anchors.horizontalCenter: parent.horizontalCenter
            visible: PomodoroService.state === "break" || PomodoroService.state === "paused_break"

            TextInput {
                id: activityInput
                anchors.fill: parent
                anchors.margins: 8
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                property string placeholderText: "¿Qué hiciste en este ciclo?"

                Text {
                    anchors.fill: parent
                    anchors.verticalCenter: parent.verticalCenter
                    text: activityInput.placeholderText
                    color: "#666666"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    visible: !activityInput.text && !activityInput.activeFocus
                }

                onAccepted: {
                    pomodoroOverlay.activityText = text
                    PomodoroService.log(text)
                    text = ""
                }
            }
        }

        // Botón guardar
        Rectangle {
            width: 120
            height: 32
            radius: 8
            color: saveArea.containsMouse ? "#3a3a3a" : "#2a2a2a"
            border.color: "#555555"
            border.width: 1
            anchors.horizontalCenter: parent.horizontalCenter
            visible: (PomodoroService.state === "break" || PomodoroService.state === "paused_break") && activityInput.text.length > 0

            Text {
                anchors.centerIn: parent
                text: "\uf0c7 Guardar"
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            MouseArea {
                id: saveArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    PomodoroService.log(activityInput.text)
                    activityInput.text = ""
                }
            }
        }

        // Botones de continuar/detener cuando el break termina
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            visible: PomodoroService.state === "break_done"

            Rectangle {
                width: 140
                height: 40
                radius: 8
                color: continueArea.containsMouse ? "#4a4a4a" : "#3a3a3a"
                border.color: "#666666"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "\uf04b Continuar"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                MouseArea {
                    id: continueArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PomodoroService.continueNext()
                }
            }

            Rectangle {
                width: 120
                height: 40
                radius: 8
                color: stopBreakArea.containsMouse ? "#663333" : "#442222"
                border.color: "#884444"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "\uf04d Detener"
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                MouseArea {
                    id: stopBreakArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PomodoroService.stop()
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (PomodoroService.state !== "break_done")
                PomodoroService.skip()
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36
        anchors.horizontalCenter: parent.horizontalCenter
        text: PomodoroService.state === "break_done" ? "" : "clic para saltar"
        color: "#555"
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
