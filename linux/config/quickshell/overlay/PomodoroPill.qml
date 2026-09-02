import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

PanelWindow {
    id: pomodoroPill
    visible: PomodoroService.active && PomodoroService.state !== "break" && PomodoroService.state !== "paused_break"
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    // Posición y tamaño dinámicos (persistencia en pomodoro.conf)
    property int posX: PomodoroService.pillX !== undefined ? PomodoroService.pillX : 100
    property int posY: PomodoroService.pillY !== undefined ? PomodoroService.pillY : 48

    implicitWidth: PomodoroService.pillWidth !== undefined ? PomodoroService.pillWidth : 120
    implicitHeight: PomodoroService.pillHeight !== undefined ? PomodoroService.pillHeight : 32

    anchors {
        top: true
        left: true
    }
    margins {
        top: posY
        left: posX
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Math.min(parent.width, parent.height) / 2
        color: "#000000"
        border.color: "#333333"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: PomodoroService.paused ? "\uf04c" : ((PomodoroService.state === "break" || PomodoroService.state === "paused_break") ? "\uf0f4" : "\uf252")
                color: (PomodoroService.state === "break" || PomodoroService.state === "paused_break") ? "#eba0ac" : (PomodoroService.paused ? "#aaaaaa" : "white")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(10, Math.min(16, pomodoroPill.height * 0.4))
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: PomodoroService.fmt(PomodoroService.remaining)
                color: (PomodoroService.state === "break" || PomodoroService.state === "paused_break") ? "#eba0ac" : (PomodoroService.paused ? "#aaaaaa" : "white")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(11, Math.min(18, pomodoroPill.height * 0.45))
                font.bold: true
            }
        }

        // Mover
        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor
            property point pressPos: "0,0"

            onPressed: mouse => {
                pressPos = Qt.point(mouse.x, mouse.y);
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    const newX = Math.max(0, pomodoroPill.posX + (mouse.x - pressPos.x));
                    const newY = Math.max(0, pomodoroPill.posY + (mouse.y - pressPos.y));
                    pomodoroPill.posX = newX;
                    pomodoroPill.posY = newY;
                }
            }
            onReleased: {
                PomodoroService.setConfig("pill_x", pomodoroPill.posX);
                PomodoroService.setConfig("pill_y", pomodoroPill.posY);
            }
            onClicked: {
                UIState.dateMenuSection = "pomodoro";
                UIState.dateMenuOpen = true;
            }
        }

        // Redimensionar (Esquina inferior derecha)
        Rectangle {
            width: 10
            height: 10
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeFDiagCursor
                property point pressPos: "0,0"

                onPressed: mouse => {
                    pressPos = Qt.point(mouse.x, mouse.y);
                }
                onPositionChanged: mouse => {
                    if (pressed) {
                        const newW = Math.max(80, pomodoroPill.implicitWidth + (mouse.x - pressPos.x));
                        const newH = Math.max(24, pomodoroPill.implicitHeight + (mouse.y - pressPos.y));
                        pomodoroPill.implicitWidth = newW;
                        pomodoroPill.implicitHeight = newH;
                    }
                }
                onReleased: {
                    PomodoroService.setConfig("pill_width", pomodoroPill.implicitWidth);
                    PomodoroService.setConfig("pill_height", pomodoroPill.implicitHeight);
                }
            }
        }
    }
}
