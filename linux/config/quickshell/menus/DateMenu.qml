import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../config"

PopupWindow {
    id: dateMenu
    implicitWidth: 320
    implicitHeight: 150
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.dateMenuOpen
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
            Text { text: "Calendario, tareas y actividad aparecerán aquí"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 10; wrapMode: Text.WordWrap }
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
