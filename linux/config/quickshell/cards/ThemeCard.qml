import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: themeCard
    width: parent.width
    height: 64
    radius: 14
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.activeSection === "monitoreo" || UIState.activeSection === "pantallas"

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 12
        spacing: 10

        RowLayout {
            width: parent.width

            Text {
                text: ThemeService.themeLight ? "\uf185" : "\uf186"
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                Layout.preferredWidth: 28
            }

            Column {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: "TEMA"
                    color: "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }

                Text {
                    text: ThemeService.themeLight ? "Modo claro" : "Modo oscuro"
                    color: ThemeService.themeLight ? "white" : "#aaa"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                }
            }

            Rectangle {
                width: 54
                height: 30
                radius: 9
                color: themeToggleArea.containsMouse ? "white" : ThemeService.themeLight ? "#141414" : "#141414"
                border.color: ThemeService.themeLight ? "white" : "#333"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: ThemeService.themeLight ? "LIGHT" : "DARK"
                    color: themeToggleArea.containsMouse ? "#000000" : ThemeService.themeLight ? "white" : "#555"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                }

                MouseArea {
                    id: themeToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: ThemeService.toggle()
                }
            }
        }
    }

    onVisibleChanged: if (visible) ThemeService.refresh()
}