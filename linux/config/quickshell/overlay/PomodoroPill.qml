import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

// Pill flotante del pomodoro: visible solo con el timer activo (fase
// trabajo/descanso, incluso pausado). Clic → abre el centro en POMODORO.
PanelWindow {
    id: pomodoroPill
    visible: PomodoroService.active
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    implicitWidth: 92
    implicitHeight: 26

    anchors { top: true; right: true }
    margins { top: 48; right: 12 }

    Rectangle {
        anchors.fill: parent
        radius: 13
        color: "#000000"
        border.color: "#333"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: PomodoroService.paused ? "\uf04c" : ((PomodoroService.state === "break" || PomodoroService.state === "paused_break") ? "\uf0f4" : "\uf252")
                color: (PomodoroService.state === "break" || PomodoroService.state === "paused_break") ? "#eba0ac" : (PomodoroService.paused ? "#aaaaaa" : "white")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: PomodoroService.fmt(PomodoroService.remaining)
                color: (PomodoroService.state === "break" || PomodoroService.state === "paused_break") ? "#eba0ac" : (PomodoroService.paused ? "#aaaaaa" : "white")
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                UIState.dateMenuSection = "pomodoro";
                UIState.dateMenuOpen = true;
            }
        }
    }
}
