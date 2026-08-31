import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import ".."
import "../config"
import "../services"

Card {
    id: systemCard
    cIcon: "\uf080"
    cAccent: DashboardService.rootDisk >= 90 ? "#eba0ac" : "white"
    cTitle: "SISTEMA"
    cBig: DashboardService.rootDisk + "%"
    cVal: DashboardService.rootDisk
    cSub: "Carga " + DashboardService.systemLoad + " · Up " + DashboardService.systemUptime
    dDel: 240
    cardOn: UIState.widgetMenuOpen
    visible: UIState.activeSection === "monitoreo"
    MouseArea { anchors.fill: parent; onClicked: DashboardService.openMonitorDetail("sistema") }
}