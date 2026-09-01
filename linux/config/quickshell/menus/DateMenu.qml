import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../config"
import "../components"

// Centro personal: tareas de la nota diaria de Obsidian + pomodoro
// configurable. Se abre al clicar el reloj de la barra.
PopupWindow {
    id: dateMenu
    implicitWidth: 320
    implicitHeight: 468
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.dateMenuOpen
    readonly property string section: UIState.dateMenuSection
    property string clockFull: ""

    anchor { window: root; rect.x: (root.width - dateMenu.implicitWidth) / 2; rect.y: root.height + 8 }
    onOpenedChanged: if (!opened) UIState.hoversReset()
    onVisibleChanged: { if (!visible && UIState.dateMenuOpen) UIState.dateMenuOpen = false; }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 14
        color: "#000000"
        border.color: "#333"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Text { text: "CENTRO DE TAREAS"; color: "white"; font.family: fontFamily; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2 }
            Text { text: clockFull; color: "white"; font.family: fontFamily; font.pixelSize: 22; font.bold: true }

            Row {
                spacing: 8

                Rectangle {
                    width: (dateMenu.implicitWidth - 48) / 2
                    height: 26
                    radius: 8
                    color: dateMenu.section === "tareas" ? Theme.bgHover : Theme.bgItem
                    border.color: dateMenu.section === "tareas" ? Theme.fgFaint : Theme.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "\uf02c  TAREAS"
                        color: dateMenu.section === "tareas" ? "white" : Theme.fgDim
                        font.family: dateMenu.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UIState.dateMenuSection = "tareas"
                    }
                }

                Rectangle {
                    width: (dateMenu.implicitWidth - 48) / 2
                    height: 26
                    radius: 8
                    color: dateMenu.section === "pomodoro" ? Theme.bgHover : Theme.bgItem
                    border.color: dateMenu.section === "pomodoro" ? Theme.fgFaint : Theme.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "\uf017  POMODORO"
                        color: dateMenu.section === "pomodoro" ? "white" : Theme.fgDim
                        font.family: dateMenu.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UIState.dateMenuSection = "pomodoro"
                    }
                }
            }

            TasksTab { visible: dateMenu.section === "tareas" }
            PomodoroTab { visible: dateMenu.section === "pomodoro" }
        }
    }

    Process {
        id: runDateFull
        command: ["date", "+%A %d de %B %Y %H:%M:%S %Z"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: clockFull = this.text.trim()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: runDateFull.running = true
    }
}
