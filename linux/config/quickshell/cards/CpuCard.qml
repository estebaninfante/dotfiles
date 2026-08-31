import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../config"
import "../services"

Card {
    id: cpuCard
    cIcon: "\uf2db"
    cAccent: DashboardService.cpuTemp >= 90 ? "#eba0ac" : DashboardService.cpuTemp >= 75 ? "white" : "white"
    cTitle: "CPU"
    cBig: Math.round(DashboardService.cpuUsage) + "%"
    cVal: DashboardService.cpuUsage
    cSub: DashboardService.cpuTemp > 0 ? Math.round(DashboardService.cpuTemp) + "°C" : "Temperatura ---"
    dDel: 180
    cardOn: UIState.widgetMenuOpen
    visible: UIState.activeSection === "monitoreo"
    MouseArea { anchors.fill: parent; onClicked: DashboardService.openMonitorDetail("cpu") }
}