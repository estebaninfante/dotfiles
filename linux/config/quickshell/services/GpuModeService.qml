pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "../config"

Item {
    id: gpuModeService

    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: batt != null && batt.isPresent && batt.type === UPowerDeviceType.Battery
    property string modo: ""
    property string fuente: ""
    property string acpi: ""

    function toggle() {
        const p = gpuToggle;
        p.running = false;
        p.running = true;
    }

    Process {
        id: gpuStatus
        command: ["gpu-mode.sh", "status"]
        running: gpuModeService.hasBattery

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let m = line.match(/Modo:\s*(\w+)/);
                if (m) gpuModeService.modo = m[1];
                m = line.match(/Fuente:\s*(\w+)/);
                if (m) gpuModeService.fuente = m[1];
                m = line.match(/ACPI:\s*(\w+)/);
                if (m) gpuModeService.acpi = m[1];
            }
        }
    }

    Timer {
        interval: 5000
        running: gpuModeService.hasBattery
        repeat: true
        onTriggered: gpuStatus.running = true
    }

    Process {
        id: gpuToggle
        command: ["gpu-mode.sh", "toggle"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const p = gpuStatus;
                p.running = false;
                p.running = true;
            }
        }
    }
}