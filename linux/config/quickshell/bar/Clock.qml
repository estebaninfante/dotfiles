import QtQuick
import "../config"
import "../services"

Row {
    id: clockRow
    anchors.centerIn: parent
    spacing: 8

    Text {
        id: clockText
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
        text: ClockService.clockText
    }

    Text {
        id: countdownText
        color: "#cba6f7"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
        text: "→ " + ClockService.countdownText
        visible: ClockService.countdownText !== "🎉"
    }

    MouseArea {
        id: clockArea
        anchors.fill: parent
        z: 2
        hoverEnabled: true
        onClicked: UIState.dateMenuOpen = !UIState.dateMenuOpen
    }
}