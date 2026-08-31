import QtQuick
import "../config"
import "../services"

Rectangle {
    id: bar
    color: "#000000"
    bottomLeftRadius: 15
    bottomRightRadius: 15
    width: parent.width * 0.985
    height: parent.height
    anchors.horizontalCenter: parent.horizontalCenter
    clip: true
    opacity: expanded ? 1 : 0

    required property bool expanded

    Workspaces {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    Clock {
        anchors.centerIn: parent
    }

    RamIndicator {
        id: ramRow
        anchors.right: BatteryService.hasBattery ? batteryRow.left : menuRow.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
    }

    BatteryIndicator {
        id: batteryRow
        anchors.right: menuRow.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
    }

    TrayButtons {
        id: menuRow
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
    }
}