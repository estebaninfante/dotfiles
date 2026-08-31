import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../components"
import "../cards"

PopupWindow {
    id: widgetMenu
    implicitWidth: 520
    implicitHeight: menuCol.implicitHeight
    visible: opened
    grabFocus: true
    color: "transparent"

    required property PanelWindow root
    property bool opened: UIState.widgetMenuOpen

    onVisibleChanged: {
        if (!visible)
            UIState.widgetMenuOpen = false;
    }

    function refreshConnections() {
        if (UIState.activeSection !== "conexiones")
            return;
        if (wifiCard.wifiOn && !wifiCard.wifiScanning)
            wifiCard.refreshNetworks();
        if (bluetoothCard.btOn && !bluetoothCard.btScanning)
            bluetoothCard.refreshDevices();
    }

    function refreshAudio() {
        if (UIState.activeSection !== "dispositivos")
            return;
        AudioService.scanAudioDevices();
        audioCard.refreshCameras();
    }

    function refreshScreens() {
        if (UIState.activeSection === "pantallas")
            screenCard.refresh();
    }

    function refreshMonitoring() {
        DashboardService.refreshMonitoring();
    }

    onOpenedChanged: {
        if (opened) {
            initialRefresh.restart();
            refreshAudio();
            refreshScreens();
            refreshMonitoring();
        } else {
            UIState.hoversReset();
        }
    }

    Timer {
        id: initialRefresh
        interval: 700
        repeat: false
        onTriggered: widgetMenu.refreshConnections()
    }

    anchor {
        window: root
        rect.x: root.width - widgetMenu.implicitWidth - 12
        rect.y: root.height + 8
    }

    Column {
        id: menuCol
        anchors.fill: parent
        spacing: 12

        Rectangle {
            width: parent.width
            height: cards.implicitHeight + 32
            radius: 18
            color: "#000000"
            border.color: "#333"
            border.width: 1
            visible: UIState.monitorDetail === ""
            opacity: UIState.widgetMenuOpen ? 1 : 0
            scale: UIState.widgetMenuOpen ? 1 : 0.94
            transformOrigin: Item.TopRight

            Column {
                id: cards
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 16
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                visible: UIState.monitorDetail === ""

                Flickable {
                    width: parent.width
                    height: 36
                    clip: true
                    contentWidth: sectionRow.implicitWidth
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: sectionRow
                        spacing: 6

                        Repeater {
                            model: ["CONEXIONES", "MONITOREO", "PANTALLAS", "DISPOSITIVOS", "NOTIFICACIONES"]

                            delegate: Rectangle {
                                required property string modelData
                                width: Math.max(84, sectionLabel.implicitWidth + 24)
                                height: 32
                                radius: 9
                                color: UIState.activeSection === modelData.toLowerCase() ? "white" : sectionArea.containsMouse ? "#1d1d26" : "#141414"

                                Text {
                                    id: sectionLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: UIState.activeSection === modelData.toLowerCase() ? "#000000" : "#aaa"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                }

                                MouseArea {
                                    id: sectionArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        UIState.activeSection = modelData.toLowerCase();
                                        widgetMenu.refreshAudio();
                                        widgetMenu.refreshScreens();
                                        widgetMenu.refreshMonitoring();
                                    }
                                }
                            }
                        }
                    }
                }

                ThemeCard { id: themeCard }
                RamCard { id: ramCard }
                BattCard { id: battCard }
                GpuCard { id: gpuCard }
                AudioCard { id: audioCard }
                CpuCard { id: cpuCard }
                SystemCard { id: systemCard }
                ScreenCard { id: screenCard }
                WifiCard { id: wifiCard }
                BluetoothCard { id: bluetoothCard }
                NotifCard { id: notifCard }
            }

            Rectangle {
                id: closeBtn
                width: 20
                height: 20
                radius: 6
                color: closeArea.containsMouse ? "white" : "transparent"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.rightMargin: 14

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d"
                    color: closeArea.containsMouse ? "#000000" : "#888"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: closeArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: UIState.widgetMenuOpen = false
                }
            }
        }

        MonitorDetail {}
    }
}