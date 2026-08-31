import QtQuick
import "../config"
import "../services"
import "../components"

Row {
    id: menuRow
    spacing: 6

    Rectangle {
        id: brightnessIndicator
        visible: BatteryService.hasBattery
        width: 60
        height: 22
        radius: 8
        color: UIState.brightnessMenuOpen ? "white" : brightnessArea.containsMouse ? "#1d1d26" : "#141414"

        Text {
            anchors.centerIn: parent
            text: "\uf185 " + Math.round(BrightnessService.brightnessPct) + "%"
            color: UIState.brightnessMenuOpen ? "#000000" : "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }

        MouseArea {
            id: brightnessArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: UIState.brightnessMenuOpen = !UIState.brightnessMenuOpen
            onWheel: wheel => BrightnessService.adjust(wheel.angleDelta.y > 0)
        }
    }

    Rectangle {
        id: volumeIndicator
        width: 62
        height: 22
        radius: 8
        color: UIState.volumeMenuOpen ? "white" : volumeArea.hov ? "#1d1d26" : "#141414"

        Text {
            anchors.centerIn: parent
            text: AudioService.volumeMuted ? "\uf026" : "\uf028 " + Math.round(AudioService.volumePct) + "%"
            color: UIState.volumeMenuOpen ? "#000000" : "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }

        MouseArea {
            id: volumeArea
            property bool hov: false
            anchors.fill: parent
            hoverEnabled: true
            onEntered: hov = true
            onExited: hov = false
            onClicked: UIState.volumeMenuOpen = !UIState.volumeMenuOpen
            onWheel: wheel => AudioService.adjustVolume(wheel.angleDelta.y > 0)
        }
    }

    Connections {
        target: UIState
        function onHoversReset() { volumeArea.hov = false }
    }

    IconButton {
        id: ccBtn
        icon: "\uf137"
        iconPixelSize: 13
        opened: UIState.controlCenterOpen
        onClicked: UIState.controlCenterOpen = !UIState.controlCenterOpen
    }

    IconButton {
        id: menuBtn
        icon: "\uf009"
        iconPixelSize: 14
        opened: UIState.widgetMenuOpen
        onClicked: UIState.widgetMenuOpen = !UIState.widgetMenuOpen
    }
}