import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"

PopupWindow {
    id: ramMenu
    implicitWidth: 300
    implicitHeight: 300
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.ramMenuOpen
    property var processes: ListModel {}
    property string ramBarText: "--%"

    anchor { window: root; rect.x: root.width - ramMenu.implicitWidth - 190; rect.y: root.height + 8 }
    onVisibleChanged: { if (!visible) opened = false; }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 14
        color: "#000000"
        border.color: "#333"
        border.width: 1
        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            RowLayout {
                width: parent.width
                Text { text: "RAM"; color: "white"; font.family: fontFamily; font.pixelSize: 13; font.bold: true }
                Item { Layout.fillWidth: true }
                Text { text: ramBarText; color: "white"; font.family: fontFamily; font.pixelSize: 11 }
            }
            Text { text: "10 PROCESOS CON MAYOR CONSUMO"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 9; font.bold: true }
            ListView {
                width: parent.width
                height: 220
                clip: true
                spacing: 4
                model: processes
                delegate: Rectangle {
                    required property string processName
                    required property string memory
                    width: parent ? parent.width : 0
                    height: 26
                    radius: 6
                    color: "#000000"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        Text { text: processName; color: "white"; font.family: fontFamily; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: memory + " MB"; color: "white"; font.family: fontFamily; font.pixelSize: 9 }
                    }
                }
            }
            Text { text: processes.count ? "Ordenados por RAM usada" : "Leyendo procesos..."; color: "#555"; font.family: fontFamily; font.pixelSize: 9 }
        }
    }

    Process {
        id: ramMenuStatus
        command: ["bash", "-c", "ps -eo comm=,rss= --sort=-rss | awk 'NR <= 10 {printf \"%s|%.0f\\n\", $1, $2/1024}'"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { const p = line.trim().split("|"); if (p.length === 2) processes.append({ processName: p[0], memory: p[1] }); }
        }
    }

    Process {
        id: runMem
        command: ["bash", "-c", "free -m | awk '/Mem:/{printf \"%.0f\", ($2-$7)/$2*100}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const p = parseFloat(this.text);
                ramBarText = p + "%";
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: runMem.running = true
    }

    onOpenedChanged: {
        if (opened) {
            processes.clear();
            ramMenuStatus.running = true;
        } else {
            UIState.hoversReset();
        }
    }
}
