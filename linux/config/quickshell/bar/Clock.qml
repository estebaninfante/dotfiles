import QtQuick
import "../config"
import "../services"

Text {
    id: clock
    anchors.centerIn: parent
    color: "white"
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 12
    text: ClockService.clockText

    MouseArea {
        id: clockArea
        anchors.fill: parent
        z: 2
        hoverEnabled: true
        onClicked: UIState.dateMenuOpen = !UIState.dateMenuOpen
    }
}