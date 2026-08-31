import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: monitorDetail

    readonly property int menuWidth: 520

    width: parent.width
    implicitHeight: detailCol.implicitHeight + 32
    radius: 18
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.monitorDetail !== ""
    opacity: UIState.monitorDetail !== "" ? 1 : 0
    scale: UIState.monitorDetail !== "" ? 1 : 0.94
    transformOrigin: Item.TopRight

    Column {
        id: detailCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 16
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 10

        RowLayout {
            width: parent.width
            Text {
                text: "\uf060  DETALLE  /  " + UIState.monitorDetail.toUpperCase()
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 1.5
                Layout.fillWidth: true
                MouseArea { id: detailBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: UIState.monitorDetail = "" }
            }
        }

        Text {
            width: parent.width
            text: UIState.monitorDetail === "cpu" ? "Procesador, temperatura y uso por hilo l\u00f3gico" : UIState.monitorDetail === "gpu" ? "Uso, memoria, temperatura y consumo NVIDIA" : UIState.monitorDetail === "ram" ? "Memoria disponible y procesos con mayor consumo" : "Carga general, almacenamiento y sesi\u00f3n"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: UIState.monitorDetail === "cpu" ? [["USO", Math.round(DashboardService.cpuUsage) + "%"], ["TEMPERATURA M\u00c1XIMA", Math.round(DashboardService.cpuTemp) + " \u00b0C"], ["CARGA 1 MIN", DashboardService.systemLoad], ["N\u00daCLEOS", "Detectados por kernel"]] : UIState.monitorDetail === "gpu" ? [["USO GPU", Math.round(DashboardService.gpuUsage) + "%"], ["TEMPERATURA", Math.round(DashboardService.gpuTemp) + " \u00b0C"], ["MEMORIA", Math.round(DashboardService.gpuMemory) + " / " + Math.round(DashboardService.gpuMemoryTotal) + " MB"], ["CONSUMO", Math.round(DashboardService.gpuPower) + " / " + Math.round(DashboardService.gpuPowerLimit) + " W"]] : [["DISCO /", DashboardService.rootDisk + "% usado"], ["CARGA", DashboardService.systemLoad], ["TIEMPO ENCENDIDO", DashboardService.systemUptime]]
            delegate: Rectangle {
                required property var modelData
                width: monitorDetail.menuWidth - 32
                height: 42
                radius: 7
                color: "#000000"
                visible: UIState.monitorDetail !== "ram" && UIState.monitorDetail !== "cpu"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    Text { text: modelData[0]; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 11; Layout.fillWidth: true }
                    Text { text: modelData[1]; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 12; font.bold: true }
                }
            }
        }

        Text {
            text: "PROCESOS RAM"
            color: "#aaa"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.bold: true
            visible: UIState.monitorDetail === "ram"
        }
        Repeater {
            model: DashboardService.ramProcesses
            delegate: RowLayout {
                width: monitorDetail.menuWidth - 32
                visible: UIState.monitorDetail === "ram"
                Text { text: processName; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: memory + " MB"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 9 }
            }
        }

        Text { text: "USO POR HILO L\u00d3GICO"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true; visible: UIState.monitorDetail === "cpu" }
        Grid {
            columns: 4
            columnSpacing: 6
            rowSpacing: 6
            width: parent.width
            visible: UIState.monitorDetail === "cpu"
            Repeater {
                model: DashboardService.cpuThreads
                delegate: Rectangle {
                    required property string threadName
                    required property string threadUsage
                    width: (monitorDetail.menuWidth - 50) / 4
                    height: 38
                    radius: 6
                    color: "#000000"
                    Column {
                        anchors.centerIn: parent
                        Text { text: threadName.toUpperCase(); color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: Math.round(parseFloat(threadUsage)) + "%"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
        }

        Text { text: "Actualizaci\u00f3n autom\u00e1tica cada 2.5 s"; color: "#555"; font.family: Theme.fontFamily; font.pixelSize: 9 }
    }
}