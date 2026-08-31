import QtQuick
import Quickshell.Hyprland

Row {
    spacing: 5

    Repeater {
        model: Hyprland.workspaces

        delegate: Rectangle {
            id: workspaceBox
            width: mouseArea.containsMouse ? 40 : modelData.focused ? 35 : 30
            color: modelData.focused ? "white" : mouseArea.containsMouse ? "#1d1d26" : "#141414"
            height: 19
            radius: 8

            Text {
                id: workspaceText
                text: modelData.id
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                color: modelData.focused ? "#000000" : mouseArea.containsMouse ? "white" : "white"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            MouseArea {
                id: mouseArea
                hoverEnabled: true
                anchors.fill: parent

                onClicked: {
                    modelData.activate();
                }
            }
        }
    }
}