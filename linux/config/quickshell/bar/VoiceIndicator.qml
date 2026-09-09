import QtQuick
import "../config"
import "../services"

Rectangle {
    id: voiceRow
    width: voiceInner.implicitWidth + 16
    height: 22
    radius: 8
    color: VoiceService.handyRunning ? "#1e1e2e" : voiceArea.containsMouse ? "#1d1d26" : "#141414"

    property bool isActive: VoiceService.handyRunning || VoiceService.loopActive

    function icon() {
        if (VoiceService.handyRunning)
            return "\uf130";  // microphone
        if (VoiceService.loopActive)
            return "\uf0e7";  // bolt (loop active)
        return "\uf130";      // microphone (inactive)
    }

    function statusColor() {
        if (VoiceService.handyRunning)
            return "#a6e3a1";  // green - recording
        if (VoiceService.loopActive)
            return "#89b4fa";  // blue - loop active
        return "#6c7086";      // gray - inactive
    }

    Row {
        id: voiceInner
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: voiceIcon
            text: voiceRow.icon()
            color: voiceRow.statusColor()
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12

            SequentialAnimation on opacity {
                loops: VoiceService.handyRunning ? Animation.Infinite : 1
                running: VoiceService.handyRunning
                NumberAnimation { from: 1; to: 0.4; duration: 800 }
                NumberAnimation { from: 0.4; to: 1; duration: 800 }
            }
        }

        Text {
            id: voiceText
            text: VoiceService.handyRunning ? "ESCUCHANDO" : VoiceService.loopActive ? "LOOP" : "VOICE"
            color: voiceRow.statusColor()
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
        }
    }

    MouseArea {
        id: voiceArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (VoiceService.loopActive) {
                // Stop loop
                loopStopProc.running = false;
                loopStopProc.running = true;
            } else {
                // Start loop
                loopStartProc.running = false;
                loopStartProc.running = true;
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

    Behavior on color { ColorAnimation { duration: 150 } }
}