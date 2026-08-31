import QtQuick
import "../config"

Rectangle {
    id: iconButton
    width: buttonWidth
    height: buttonHeight
    radius: 8
    color: opened ? "white" : area.hov ? "#1d1d26" : "#141414"

    property string icon: ""
    property string text: ""
    property bool opened: false
    property int buttonWidth: 32
    property int buttonHeight: 22
    property int iconPixelSize: 13
    signal clicked()
    signal wheeled(int delta)

    Connections {
        target: UIState
        function onHoversReset() { area.hov = false }
    }

    Text {
        anchors.centerIn: parent
        text: iconButton.text.length > 0 ? iconButton.icon + " " + iconButton.text : iconButton.icon
        color: iconButton.opened ? "#000000" : "white"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: iconButton.iconPixelSize
    }

    MouseArea {
        id: area
        property bool hov: false
        anchors.fill: parent
        hoverEnabled: true
        onEntered: hov = true
        onExited: hov = false
        onClicked: iconButton.clicked()
        onWheel: wheel => iconButton.wheeled(wheel.angleDelta.y)
    }
}