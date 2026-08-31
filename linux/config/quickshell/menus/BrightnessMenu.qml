import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"

PopupWindow {
    id: brightnessMenu
    implicitWidth: 236
    implicitHeight: briCol.implicitHeight + 26
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    property bool opened: UIState.brightnessMenuOpen
    property double brightnessPct: 0

    anchor { window: root; rect.x: root.width - brightnessMenu.implicitWidth - 72; rect.y: root.height + 8 }
    onOpenedChanged: { if (!opened) UIState.hoversReset(); }
    onVisibleChanged: { if (!visible) opened = false; }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 12
        color: "#000000"
        border.color: "#333"
        border.width: 1
        Column {
            id: briCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            RowLayout {
                width: parent.width
                Text { text: "BRILLO"; color: "#aaa"; font.family: fontFamily; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.5 }
                Item { Layout.fillWidth: true }
                Text { text: Math.round(brightnessPct) + "%"; color: "white"; font.family: fontFamily; font.pixelSize: 10 }
            }
            Row {
                width: parent.width
                spacing: 6
                Rectangle {
                    width: parent.width - 54
                    height: 26
                    radius: 8
                    color: "#000000"
                    border.color: "#333"
                    Rectangle {
                        width: parent.width * Math.min(brightnessPct, 100) / 100
                        height: parent.height
                        radius: 8
                        color: "white"
                    }
                    Rectangle {
                        x: Math.max(0, Math.min(parent.width - this.width, parent.width * brightnessPct / 100 - this.width / 2))
                        y: (parent.height - height) / 2
                        width: 12
                        height: 12
                        radius: 6
                        color: "white"
                        Behavior on x { SmoothedAnimation { velocity: 600 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        property bool dragging: false
                        function set(pct) {
                            brightnessAdjust.command = ["brightnessctl", "set", Math.max(0, Math.min(100, pct)).toFixed(0) + "%"];
                            brightnessAdjust.running = true;
                        }
                        onPressed: { dragging = true; set(mouse.x / width * 100) }
                        onPositionChanged: { if (dragging) set(mouse.x / width * 100) }
                        onReleased: dragging = false
                        onWheel: wheel => { brightnessAdjust.command = ["brightnessctl", "set", wheel.angleDelta.y > 0 ? "5%+" : "5%-"]; brightnessAdjust.running = true; }
                    }
                }
                TextInput {
                    id: brightnessInput
                    width: 48
                    height: 26
                    text: Math.round(brightnessPct).toString()
                    color: "white"
                    font.family: fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    selectByMouse: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    onAccepted: { brightnessAdjust.command = ["brightnessctl", "set", Math.max(0, Math.min(100, parseFloat(text) || 0)).toFixed(0) + "%" ]; brightnessAdjust.running = true; focus = false; }
                    Rectangle { anchors.fill: parent; z: -1; radius: 7; color: "#000000"; border.color: "#333" }
                }
            }
        }
    }

    Process {
        id: brightnessStatus
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,\"\",$4); print $4}'"]
        running: root.hasBattery
        stdout: StdioCollector {
            onStreamFinished: brightnessPct = parseFloat(this.text.trim()) || 0
        }
    }

    Process {
        id: brightnessAdjust
        command: ["brightnessctl", "set", "5%+"]
        running: false
        onExited: brightnessStatus.running = true
    }
}
