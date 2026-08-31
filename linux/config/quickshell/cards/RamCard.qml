import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: ramCard
    width: parent.width
    height: ramProcessesOpen ? 96 + DashboardService.ramProcesses.count * 16 : 84
    radius: 14
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.activeSection === "monitoreo"
    property double usedGiB: 0
    property double totGiB: 0
    property double usedPct: 0
    property bool ramProcessesOpen: false

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 8
        RowLayout {
            width: parent.width
            Text { text: "\uf538"; color: "white"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 23; Layout.preferredWidth: 28 }
            Text { text: "RAM"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true }
            Text { text: Math.round(ramCard.usedPct) + "%"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 20 }
            Item { Layout.fillWidth: true }
            Text { text: ramCard.usedGiB.toFixed(1) + "G / " + ramCard.totGiB.toFixed(1) + "G"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 10 }
        }
        Rectangle { width: parent.width; height: 5; radius: 3; color: "#000000"; Rectangle { width: parent.width * ramCard.usedPct / 100; height: parent.height; radius: 3; color: ramCard.usedPct > 90 ? "#eba0ac" : "white" } }
        Column {
            id: ramProcesses
            width: parent.width
            spacing: 3
            visible: ramCard.ramProcessesOpen
            Repeater {
                model: DashboardService.ramProcesses
                delegate: RowLayout {
                    width: ramProcesses.width
                    Text { text: processName; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: memory + " MB"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                }
            }
        }
    }
    MouseArea { anchors.fill: parent; z: 1; onClicked: DashboardService.openMonitorDetail("ram") }

    Process {
        id: ramFree
        command: ["bash", "-c", "free -m | awk '/Mem:/{printf \"%d %d\", ($2-$7), $2}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(/\s+/);
                if (parts.length === 2) {
                    const usedMiB = parseFloat(parts[0]);
                    const totMiB = parseFloat(parts[1]);
                    if (totMiB > 0) { ramCard.usedPct = usedMiB / totMiB * 100; ramCard.usedGiB = usedMiB / 1024; ramCard.totGiB = totMiB / 1024; }
                }
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; onTriggered: ramFree.running = true }
}