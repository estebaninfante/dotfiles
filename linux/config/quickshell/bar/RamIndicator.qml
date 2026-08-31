import QtQuick
import "../config"
import "../services"

Item {
    id: ramRow
    width: 64
    height: 22

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: UIState.ramMenuOpen ? "white" : ramArea.hov ? "#1d1d26" : "#141414"
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: ramIcon
            text: "\uf2db"
            color: UIState.ramMenuOpen ? "#000000" : "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }

        Text {
            id: ramText
            text: MemoryService.pct >= 0 ? MemoryService.pct + "%" : "--%"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            color: UIState.ramMenuOpen ? "#000000" : MemoryService.pct > 90 ? "#eba0ac" : "white"
        }
    }

    MouseArea {
        id: ramArea
        property bool hov: false
        anchors.fill: parent
        z: 2
        hoverEnabled: true
        onEntered: hov = true
        onExited: hov = false
        onClicked: UIState.ramMenuOpen = !UIState.ramMenuOpen
    }
}