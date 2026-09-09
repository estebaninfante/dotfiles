import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../components"

Card {
    id: gcCard

    property bool engineRunning: false
    property int handsDetected: 0
    property int facesDetected: 0

    cIcon: "\uf040"
    cAccent: gcCard.engineRunning ? "#a6e3a1" : "#555"
    cTitle: "GESTURE CONTROL"
    cBig: gcCard.engineRunning ? "Activo" : "Inactivo"
    cSub: gcCard.engineRunning
        ? gcCard.handsDetected + " manos · " + gcCard.facesDetected + " caras"
        : "Click para iniciar"
    cVal: gcCard.engineRunning ? 100 : 0
    dDel: 50
    cardOn: UIState.widgetMenuOpen
    visible: UIState.activeSection === "dispositivos"

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: gcCard.toggleEngine()
    }

    function toggleEngine() {
        if (gcCard.engineRunning) {
            gcStop.running = false;
            gcStop.running = true;
        } else {
            gcStart.running = false;
            gcStart.running = true;
        }
    }

    function openConfig() {
        gcOpenConfig.running = false;
        gcOpenConfig.running = true;
    }

    // Poll engine status
    Process {
        id: gcStatus
        command: ["bash", "-c", "systemctl --user is-active gesturecontrol-engine.service"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: gcCard.engineRunning = this.text.trim() === "active"
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: { gcStatus.running = false; gcStatus.running = true; }
    }

    // Poll hand/face count from SSE
    Process {
        id: gcHands
        command: ["bash", "-c", "curl -s --max-time 2 http://127.0.0.1:7071/state 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); h=d.get('hands',{}); f=d.get('faces',[]); print(len(h),len(f))\" 2>/dev/null || echo '0 0'"]
        running: gcCard.engineRunning
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(" ");
                if (parts.length >= 2) {
                    gcCard.handsDetected = parseInt(parts[0]) || 0;
                    gcCard.facesDetected = parseInt(parts[1]) || 0;
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: gcCard.engineRunning
        repeat: true
        onTriggered: { gcHands.running = false; gcHands.running = true; }
    }

    // Start engine
    Process {
        id: gcStart
        command: ["systemctl", "--user", "start", "gesturecontrol-engine.service"]
        running: false
        onExited: { gcStatus.running = false; gcStatus.running = true; }
    }

    // Stop engine
    Process {
        id: gcStop
        command: ["systemctl", "--user", "stop", "gesturecontrol-engine.service"]
        running: false
        onExited: { gcStatus.running = false; gcStatus.running = true; }
    }

    // Open config UI in browser
    Process {
        id: gcOpenConfig
        command: ["bash", "-c", "xdg-open http://localhost:7070"]
        running: false
    }
}
