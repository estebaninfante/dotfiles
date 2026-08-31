import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../components"
import "../config"
import "../services"

Card {
    id: gpuCard
    property bool hasTelemetry: DashboardService.gpuTelemetryAvailable

    cIcon: GpuModeService.modo === "gaming" ? "\uf11b" : GpuModeService.acpi === "off" ? "\uf011" : GpuModeService.modo === "disabled" ? "\uf2db" : "\uf06c"
    cAccent: GpuModeService.modo === "gaming" ? "white" : GpuModeService.acpi === "off" ? "white" : GpuModeService.modo === "disabled" ? "white" : DashboardService.gpuTemp >= 85 ? "#eba0ac" : "white"
    cTitle: "GPU NVIDIA"
    cBig: GpuModeService.hasBattery
        ? (GpuModeService.modo === "gaming" ? "Juegos"
            : GpuModeService.acpi === "off" ? "OFF"
            : GpuModeService.modo === "disabled" ? "D3cold"
            : (gpuCard.hasTelemetry ? Math.round(DashboardService.gpuUsage) + "%" : "Auto"))
        : (gpuCard.hasTelemetry ? Math.round(DashboardService.gpuUsage) + "%" : "NO DETECTADA")
    cVal: gpuCard.hasTelemetry ? DashboardService.gpuUsage : (GpuModeService.hasBattery ? 0 : 0)
    cSub: GpuModeService.hasBattery
        ? (gpuCard.hasTelemetry
            ? Math.round(DashboardService.gpuTemp) + "\u00b0C \u00b7 " + Math.round(DashboardService.gpuMemory) + "/" + Math.round(DashboardService.gpuMemoryTotal) + " MB \u00b7 " + Math.round(DashboardService.gpuPower) + "/" + Math.round(DashboardService.gpuPowerLimit) + " W"
            : (GpuModeService.fuente ? "ACPI: " + GpuModeService.acpi : "NVIDIA inactiva"))
        : (gpuCard.hasTelemetry ? Math.round(DashboardService.gpuTemp) + "\u00b0C \u00b7 " + Math.round(DashboardService.gpuMemory) + "/" + Math.round(DashboardService.gpuMemoryTotal) + " MB \u00b7 " + Math.round(DashboardService.gpuPower) + "/" + Math.round(DashboardService.gpuPowerLimit) + " W" : "nvidia-smi no disponible")
    dDel: GpuModeService.hasBattery ? 120 : 30
    cardOn: UIState.widgetMenuOpen
    visible: UIState.activeSection === "monitoreo"

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (GpuModeService.hasBattery) {
                GpuModeService.toggle();
            } else {
                DashboardService.openMonitorDetail("gpu");
            }
        }
    }
}