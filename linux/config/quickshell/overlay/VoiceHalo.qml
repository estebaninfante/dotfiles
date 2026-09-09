import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

PanelWindow {
    id: voiceHalo
    visible: VoiceService.handyRunning || VoiceService.loopActive
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    property int posX: 0
    property int posY: 0

    implicitWidth: 280
    implicitHeight: 80

    anchors {
        bottom: true
        horizontalCenter: true
    }
    margins {
        bottom: 60
    }

    Rectangle {
        id: haloBody
        anchors.fill: parent
        radius: 40
        color: "#e60d0d12"
        border.color: VoiceService.handyRunning ? "#a6e3a1" : "#89b4fa"
        border.width: 2

        // Glow effect when recording
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.color: VoiceService.handyRunning ? "#40a6e3a1" : "#4089b4fa"
            border.width: 4
            opacity: pulseAnim.value
        }

        PropertyAnimation {
            id: pulseAnim
            target: pulseAnim
            property: "value"
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
                    text: VoiceService.handyRunning ? "ESCUCHANDO" : "LOOP ACTIVO"
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

        // Close button
        Rectangle {
            width: 24
            height: 24
            radius: 12
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            color: closeArea.containsMouse ? "#f38ba8" : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\uf00d"
                color: closeArea.containsMouse ? "#000000" : "#f38ba8"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (VoiceService.loopActive) {
                        loopStopProc.running = false;
                        loopStopProc.running = true;
                    }
                }
            }
        }

        // Click to toggle
        MouseArea {
            anchors.fill: parent
            anchors.margins: 8
            onClicked: {
                if (VoiceService.loopActive) {
                    loopStopProc.running = false;
                    loopStopProc.running = true;
                } else {
                    loopStartProc.running = false;
                    loopStartProc.running = true;
                }
            }
        }
    }

    Process {
        id: loopStartProc
        command: ["bash", "-c", "~/.local/bin/voice-loop.sh start"]
        running: false
    }

    Process {
        id: loopStopProc
        command: ["bash", "-c", "~/.local/bin/voice-loop.sh stop"]
        running: false
    }

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
}