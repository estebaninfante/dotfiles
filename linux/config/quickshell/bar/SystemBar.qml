import QtQuick
import "../config"
import "../services"

Row {
    spacing: 4

    Item {
        id: cpuPill
        width: 52
        height: 22

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: UIState.widgetMenuOpen && UIState.activeSection === "monitoreo" ? "white" : cpuArea.hov ? "#1d1d26" : "#141414"
        }

        Text {
            anchors.centerIn: parent
            text: "\uf2db " + Math.round(DashboardService.cpuUsage) + "%"
            color: UIState.widgetMenuOpen && UIState.activeSection === "monitoreo" ? "#000000" : DashboardService.cpuUsage >= 90 ? "#eba0ac" : "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 6
            height: 2
            radius: 1
            color: "#333"

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.min(1, DashboardService.cpuUsage / 100)
                color: DashboardService.cpuUsage >= 90 ? "#eba0ac" : "white"
            }
        }

        MouseArea {
            id: cpuArea
            property bool hov: false
            anchors.fill: parent
            z: 2
            hoverEnabled: true
            onEntered: hov = true
            onExited: hov = false
            onClicked: {
                UIState.activeSection = "monitoreo";
                UIState.widgetMenuOpen = !UIState.widgetMenuOpen;
            }
        }

        Connections {
            target: UIState
            function onHoversReset() { cpuArea.hov = false }
        }
    }

    Item {
        id: gpuPill
        width: 52
        height: 22
        visible: DashboardService.gpuTelemetryAvailable

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: UIState.widgetMenuOpen && UIState.activeSection === "monitoreo" ? "white" : gpuArea.hov ? "#1d1d26" : "#141414"
        }

        Text {
            anchors.centerIn: parent
            text: "\uf06c " + Math.round(DashboardService.gpuUsage) + "%"
            color: UIState.widgetMenuOpen && UIState.activeSection === "monitoreo" ? "#000000" : DashboardService.gpuUsage >= 85 ? "#eba0ac" : "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 6
            height: 2
            radius: 1
            color: "#333"

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.min(1, DashboardService.gpuUsage / 100)
                color: DashboardService.gpuUsage >= 85 ? "#eba0ac" : "white"
            }
        }

        MouseArea {
            id: gpuArea
            property bool hov: false
            anchors.fill: parent
            z: 2
            hoverEnabled: true
            onEntered: hov = true
            onExited: hov = false
            onClicked: {
                UIState.activeSection = "monitoreo";
                UIState.widgetMenuOpen = !UIState.widgetMenuOpen;
            }
        }

        Connections {
            target: UIState
            function onHoversReset() { gpuArea.hov = false }
        }
    }
}
