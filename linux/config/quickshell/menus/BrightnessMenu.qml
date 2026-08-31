import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

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
    property double brightnessPct: BrightnessService.brightnessPct

    anchor { window: root; rect.x: root.width - brightnessMenu.implicitWidth - 72; rect.y: root.height + 8 }
    onOpenedChanged: { if (!opened) UIState.hoversReset(); }
    onVisibleChanged: { if (!visible && UIState.brightnessMenuOpen) UIState.brightnessMenuOpen = false; }

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
                        onPressed: { dragging = true; BrightnessService.set(mouse.x / width * 100) }
                        onPositionChanged: { if (dragging) BrightnessService.set(mouse.x / width * 100) }
                        onReleased: dragging = false
                        onWheel: wheel => BrightnessService.adjust(wheel.angleDelta.y > 0)
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
                    onAccepted: { BrightnessService.set(parseFloat(text) || 0); focus = false; }
                    Rectangle { anchors.fill: parent; z: -1; radius: 7; color: "#000000"; border.color: "#333" }
                }
            }
        }
    }
}