import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

PanelWindow {
    id: root
    property bool superDown: false
    property bool superHeld: false
    property int expandedHeight: 30
    property int hotEdge: 3

    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: batt != null && batt.isPresent && batt.type === UPowerDeviceType.Battery
    readonly property double battPct: root.hasBattery ? root.batt.percentage * 100 : 0

    color: "transparent"
    exclusionMode: ExclusionMode.Normal

    anchors {
        top: true
        left: true
        right: true
    }

    readonly property bool expanded: hot.hovered || superHeld

    implicitHeight: expanded ? expandedHeight : hotEdge
    exclusiveZone: implicitHeight
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 80
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler {
        id: hot
    }

    onSuperDownChanged: {
        if (root.superDown) {
            root.superHeld = false;
            superHoldTimer.restart();
        } else {
            superHoldTimer.stop();
            root.superHeld = false;
        }
    }

    Timer {
        id: superHoldTimer
        interval: 250
        repeat: false
        onTriggered: root.superHeld = true
    }

    Process {
        id: superMonitor
        command: ["super-hold-monitor.sh"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data === "1")
                    root.superDown = true;
                else if (data === "0")
                    root.superDown = false;
            }
        }
    }

    Rectangle {
        bottomLeftRadius: 15
        bottomRightRadius: 15
        width: parent.width * 0.985
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter

        color: "#95000000"
        clip: true
        opacity: expanded ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 50
            }
        }

        Text {
            id: clock
            anchors.centerIn: parent
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 12
        }

        Process {
            id: runDate
            command: ["date"]
            running: true

            stdout: StdioCollector {
                onStreamFinished: clock.text = this.text
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: runDate.running = true
        }
        Row {
            id: ramRow
            anchors.right: batteryRow.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                id: ramIcon
                text: "\uf03b9"
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: 13
            }

            Text {
                id: ramText
                property double p: NaN
                text: "--%"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: ramText.p > 90 ? "#e06c75" : "white"
            }

            Process {
                id: runMem
                command: ["bash", "-c", "free -m | awk '/Mem:/{printf \"%.0f\", ($2-$7)/$2*100}'"]
                running: true

                stdout: StdioCollector {
                    onStreamFinished: {
                        ramText.p = parseFloat(this.text);
                        ramText.text = ramText.p + "%";
                    }
                }
            }

            Timer {
                interval: 3000
                running: true
                repeat: true
                onTriggered: runMem.running = true
            }
        }
        Row {
            id: batteryRow
            anchors.right: menuRow.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: root.hasBattery

            function icon() {
                const p = root.battPct;
                if (root.batt.state === UPowerDeviceState.Charging)
                    return "\uf0e7";
                if (p >= 90)
                    return "\uf240";
                if (p >= 75)
                    return "\uf241";
                if (p >= 50)
                    return "\uf242";
                if (p >= 25)
                    return "\uf243";
                return "\uf244";
            }

            Text {
                id: batteryIcon
                text: batteryRow.icon()
                color: batteryText.color
                font.family: root.fontFamily
                font.pixelSize: 13
            }

            Text {
                id: batteryText
                text: Math.round(root.battPct) + "%"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.battPct <= 20 ? "#e06c75" : root.batt.state === UPowerDeviceState.Charging ? "#98c379" : "white"
            }
        }
        Row {
            id: menuRow
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: menuBtn
                width: 26
                height: 19
                radius: 8
                color: widgetMenu.opened ? "#cba6f7" : menuBtnArea.containsMouse ? "white" : "#141414"

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "\uf009"
                    color: widgetMenu.opened ? "#0d0d12" : menuBtnArea.containsMouse ? "black" : "white"
                    font.family: root.fontFamily
                    font.pixelSize: 11
                }

                MouseArea {
                    id: menuBtnArea
                    hoverEnabled: true
                    anchors.fill: parent
                    onClicked: widgetMenu.opened = !widgetMenu.opened
                }
            }
        }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10

            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Repeater {
                model: Hyprland.workspaces

                delegate: Rectangle {
                    id: workspaceBox
                    width: mouseArea.containsMouse ? 40 : modelData.focused ? 35 : 30
                    color: modelData.focused ? "red" : mouseArea.containsMouse ? "white" : "#141414"
                    height: 19
                    radius: 8

                    Text {
                        id: workspaceText
                        text: modelData.id
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: modelData.focused ? "white" : mouseArea.containsMouse ? "black" : "white"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: mouseArea
                        hoverEnabled: true
                        anchors.fill: parent

                        onClicked: {
                            modelData.activate();
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 200
}
            }
        }
    }
}

PopupWindow {
    id: widgetMenu
    implicitWidth: 320
    implicitHeight: menuCol.implicitHeight
    visible: opened
    grabFocus: true
    color: "transparent"

    property bool opened: false

    anchor {
        window: root
        rect.x: root.width - widgetMenu.implicitWidth - 12
        rect.y: root.height + 8
    }

    Column {
        id: menuCol
        anchors.fill: parent
        spacing: 8

        Rectangle {
            width: parent.width
            height: cards.implicitHeight + 22
            radius: 14
            color: "#0d0d12"
            border.color: "#26262e"
            border.width: 1

            Column {
                id: cards
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 11
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                spacing: 10

                RowLayout {
                    width: parent.width
                    height: 22

                    Text {
                        text: "SISTEMA"
                        color: "#9a9aa7"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.letterSpacing: 3
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        id: closeBtn
                        width: 20
                        height: 20
                        radius: 6
                        color: closeArea.containsMouse ? "#e06c75" : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            color: closeArea.containsMouse ? "white" : "#8a8a99"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: closeArea
                            hoverEnabled: true
                            anchors.fill: parent
                            onClicked: widgetMenu.opened = false
                        }
                    }
                }

                Card {
                    id: ramCard
                    cIcon: "\uf03b9"
                    cAccent: "#cba6f7"
                    cTitle: "RAM"
                    cBig: "--%"
                    cSub: "---"
                    cardOn: widgetMenu.opened

                    property double usedGiB: 0
                    property double totGiB: 0

                    Process {
                        id: ramFree
                        command: ["bash", "-c", "free -m | awk '/Mem:/{printf \"%d %d\", ($2-$7), $2}'"]
                        running: true

                        stdout: StdioCollector {
                            onStreamFinished: {
                                const parts = this.text.trim().split(/\s+/);
                                if (parts.length === 2) {
                                    const usedMiB = parseFloat(parts[0]);
                                    const totMiB = parseFloat(parts[1]);
                                    if (totMiB > 0) {
                                        ramCard.cVal = usedMiB / totMiB * 100;
                                        ramCard.cBig = Math.round(ramCard.cVal) + "%";
                                        ramCard.usedGiB = usedMiB / 1024;
                                        ramCard.totGiB = totMiB / 1024;
                                        ramCard.cSub = ramCard.usedGiB.toFixed(1) + "G usada · " + ramCard.totGiB.toFixed(1) + "G";
                                    }
                                }
                            }
                        }
                    }

                    Timer {
                        interval: 3000
                        running: true
                        repeat: true
                        onTriggered: ramFree.running = true
                    }
                }

                Card {
                    id: battCard
                    cIcon: battCard.icon()
                    cAccent: root.batt && root.batt.state === UPowerDeviceState.Charging ? "#98c379" : "#e06c75"
                    cTitle: "BATER\u00cdA"
                    cBig: root.hasBattery ? Math.round(root.battPct) + "%" : "--%"
                    cVal: root.battPct
                    cSub: battCard.battSub()
                    dDel: 60
                    cardOn: widgetMenu.opened
                    visible: root.hasBattery

                    function icon() {
                        if (root.batt && root.batt.state === UPowerDeviceState.Charging)
                            return "\uf0e7";
                        const p = root.battPct;
                        if (p >= 90)
                            return "\uf240";
                        if (p >= 60)
                            return "\uf242";
                        if (p >= 30)
                            return "\uf243";
                        return "\uf244";
                    }

                    function watts() {
                        const b = root.batt;
                        if (!b) return 0;
                        const t = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.timeToEmpty;
                        if (b.energy > 0 && t > 0) return b.energy * 3600 / t;
                        return 0;
                    }

                    function stateText() {
                        const s = root.batt ? root.batt.state : -1;
                        switch (s) {
                            case UPowerDeviceState.Charging: return "Cargando";
                            case UPowerDeviceState.Discharging: return "Descargando";
                            case UPowerDeviceState.FullyCharged: return "Cargada";
                            case UPowerDeviceState.Empty: return "Vac\u00eda";
                            default: return "---";
                        }
                    }

                    function fmtEta(sec) {
                        if (!sec || sec <= 0) return "";
                        const h = Math.floor(sec / 3600);
                        const m = Math.round((sec % 3600) / 60);
                        if (h >= 100) return (h / 24).toFixed(0) + "d";
                        if (h > 0) return h + "h " + String(m).padStart(2, "0") + "m";
                        return m + "m";
                    }

                    function battSub() {
                        if (!root.hasBattery) return "---";
                        let s = battCard.stateText();
                        const w = battCard.watts();
                        if (w > 0) s += " \u00b7 " + w.toFixed(1) + "W";
                        const b = root.batt;
                        const t = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.timeToEmpty;
                        const eta = battCard.fmtEta(t);
                        if (eta) s += " \u00b7 " + eta;
                        return s;
                    }
                }

                Card {
                    id: gpuCard
                    cIcon: gpuCard.modo === "gaming" ? "\uf11b" : "\uf06c"
                    cAccent: gpuCard.modo === "gaming" ? "#98c379" : "#cba6f7"
                    cTitle: "GPU NVIDIA"
                    cBig: gpuCard.modo === "gaming" ? "Juegos" : "Bater\u00eda"
                    cSub: gpuCard.fuente ? (gpuCard.modo === "gaming" ? "Click: modo bater\u00eda" : "Click: modo juegos") : "---"
                    dDel: 120
                    cardOn: widgetMenu.opened
                    visible: root.hasBattery

                    property string modo: ""
                    property string fuente: ""

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const p = gpuToggle;
                            p.running = false;
                            p.running = true;
                        }
                    }

                    Process {
                        id: gpuStatus
                        command: ["gpu-mode.sh", "status"]
                        running: true

                        stdout: SplitParser {
                            splitMarker: "\n"
                            onRead: line => {
                                let m = line.match(/Modo:\s*(\w+)/);
                                if (m) gpuCard.modo = m[1];
                                m = line.match(/Fuente:\s*(\w+)/);
                                if (m) gpuCard.fuente = m[1];
                            }
                        }
                    }

                    Timer {
                        interval: 5000
                        running: true
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
            }
        }
    }
}
    }
}
