import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

// Pantalla negra fullscreen durante el descanso visual.
PanelWindow {
    id: eyeCareOverlay
    visible: EyeCareService.onBreak

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    focusable: false

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "#000000"

    // Countdown grande al centro
    Column {
        anchors.centerIn: parent
        spacing: 18

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\uf06e"
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 64
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "MIRA A OTRO LADO"
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
            font.letterSpacing: 8
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: EyeCareService.remaining + "s"
            color: "#aaaaaa"
            font.family: Theme.fontFamily
            font.pixelSize: 48
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Descansa la vista — mira algo lejano"
            color: "#555555"
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
    }

    // Click para saltar el descanso
    MouseArea {
        anchors.fill: parent
        onClicked: {
            EyeCareService.onBreak = false
            EyeCareService.remaining = 0
            EyeCareService.startInterval()
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36
        anchors.horizontalCenter: parent.horizontalCenter
        text: "clic para saltar"
        color: "#555"
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }
}
