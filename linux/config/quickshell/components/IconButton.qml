import QtQuick

Rectangle {
    id: iconButton
    width: 32
    height: 22
    radius: 8
    color: opened ? "white" : area.hov ? "#1d1d26" : "#141414"

    property string icon: ""
    property int size: 13
    property bool opened: false
    signal clicked()

    Text {
        anchors.centerIn: parent
        text: iconButton.icon
        color: iconButton.opened ? "#000000" : "white"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: iconButton.size
    }

    MouseArea {
        id: area
        property bool hov: false
        anchors.fill: parent
        hoverEnabled: true
        onEntered: hov = true
        onExited: hov = false
        onClicked: iconButton.clicked()
    }
}