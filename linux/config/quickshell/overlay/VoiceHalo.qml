import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../config"
import "../services"

// Halo de feedback para el dictado de Handy.
//
// Posicionamiento: Quickshell's PanelWindow `anchors` SOLO soporta
// left/right/top/bottom (no existe `horizontalCenter` a nivel de panel), así
// que para centrar el halo la ventana ocupa la franja inferior completa y el
// pill se centra dentro con un `anchors.horizontalCenter` de hijo.
PanelWindow {
    id: voiceHalo
    visible: VoiceService.handyRunning || VoiceService.loopActive
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    WlrLayershell.layer: WlrLayer.Overlay

    implicitHeight: 80
    anchors {
        bottom: true
        left: true
        right: true
    }
    margins {
        bottom: 48
    }

    Rectangle {
        id: haloBody
        width: 280
        height: 80
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 40
        color: "#e60d0d12"
        border.color: VoiceService.handyRunning ? "#a6e3a1" : "#89b4fa"
        border.width: 2

        // Glow effect when recording (pulses only while Handy listens)
        property real glowOpacity: 0.3

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.color: VoiceService.handyRunning ? "#40a6e3a1" : "#4089b4fa"
            border.width: 4
            opacity: haloBody.glowOpacity
        }

        PropertyAnimation {
            id: pulseAnim
            target: haloBody
            property: "glowOpacity"
            from: 0.3
            to: 1.0
            duration: 1000
            loops: Animation.Infinite
            running: VoiceService.handyRunning
        }

        Row {
            anchors.centerIn: parent
            spacing: 12

            // Microphone icon with pulse
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: VoiceService.handyRunning ? "#30a6e3a1" : "#3089b4fa"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: VoiceService.handyRunning ? "\uf130" : "\uf0e7"
                    color: VoiceService.handyRunning ? "#a6e3a1" : "#89b4fa"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                }
            }

            // Status text
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: VoiceService.handyRunning ? "ESCUCHANDO" : "LISTO"
                    color: VoiceService.handyRunning ? "#a6e3a1" : "#89b4fa"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 2
                }

                Text {
                    text: VoiceService.lastTranscript ? VoiceService.lastTranscript.substring(0, 30) + (VoiceService.lastTranscript.length > 30 ? "..." : "") : "Di un comando..."
                    color: "#6c7086"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    width: 160
                }
            }
        }

        // Click en el halo: alterna el dictado (igual que el gesto de pulgar).
        MouseArea {
            anchors.fill: parent
            anchors.margins: 8
            onClicked: {
                toggleProc.running = false;
                toggleProc.running = true;
            }
        }
    }

    // Alterna Handy del mismo modo que el gesto (mantiene el mirror file).
    Process {
        id: toggleProc
        command: ["bash", "-c", "/home/eztvn/dotfiles/linux/bin/handy-toggle.sh"]
        running: false
    }
}
