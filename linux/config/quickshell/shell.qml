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
    property int expandedHeight: 34
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

    readonly property bool expanded: hot.hovered || superHeld || widgetMenu.opened

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
                    color: modelData.focused ? "#5D3FD3" : mouseArea.containsMouse ? "white" : "#141414"
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
             implicitWidth: 520
            implicitHeight: menuCol.implicitHeight
            visible: opened
            grabFocus: true
            color: "transparent"

             Behavior on implicitHeight {
                 NumberAnimation {
                     duration: 260
                     easing.type: Easing.OutCubic
                 }
             }

             property bool opened: false
             property string activeSection: "conexiones"

             onVisibleChanged: {
                 if (!visible)
                     opened = false;
             }

               function refreshConnections() {
                 if (activeSection !== "conexiones")
                     return;
                 if (wifiCard.wifiOn && !wifiScan.running)
                     wifiCard.refreshNetworks();
                  if (bluetoothCard.btOn && !btScan.running)
                      bluetoothCard.refreshDevices();
              }

              function refreshAudio() {
                  if (activeSection === "dispositivos" && !audioStatus.running) {
                      audioCard.sinks.clear();
                      audioCard.sources.clear();
                      audioCard.cameras.clear();
                      audioStatus.running = true;
                      cameraStatus.running = true;
                  }
              }

              onOpenedChanged: {
                  if (opened) {
                      initialRefresh.restart();
                      refreshAudio();
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
                     color: "#e60d0d12"
                     border.color: "#383847"
                     border.width: 1
                     opacity: widgetMenu.opened ? 1 : 0
                     scale: widgetMenu.opened ? 1 : 0.94
                     transformOrigin: Item.TopRight

                     Behavior on opacity {
                         NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                     }
                     Behavior on scale {
                         NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                     }
                     Behavior on height {
                         NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                     }

             Column {
                 id: cards
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                         anchors.topMargin: 16
                         anchors.leftMargin: 16
                         anchors.rightMargin: 16
                         spacing: 12

                         RowLayout {
                             width: parent.width
                             height: 24

                            Text {
                                 text: "SISTEMA  /  " + widgetMenu.activeSection.toUpperCase()
                                color: "#9a9aa7"
                                font.family: "JetBrainsMono Nerd Font"
                                 font.pixelSize: 10
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
                                     model: ["CONEXIONES", "MONITOREO", "PANTALLAS", "DISPOSITIVOS"]

                                     delegate: Rectangle {
                                         required property string modelData
                                         width: Math.max(84, sectionLabel.implicitWidth + 24)
                                         height: 32
                                         radius: 9
                                         color: widgetMenu.activeSection === modelData.toLowerCase() ? "#cba6f7" : sectionArea.containsMouse ? "#262633" : "#191922"

                                         Text {
                                             id: sectionLabel
                                             anchors.centerIn: parent
                                             text: modelData
                                             color: widgetMenu.activeSection === modelData.toLowerCase() ? "#11111b" : "#a6adc8"
                                             font.family: root.fontFamily
                                             font.pixelSize: 9
                                             font.bold: true
                                         }

                                         MouseArea {
                                             id: sectionArea
                                             anchors.fill: parent
                                             hoverEnabled: true
                                             onClicked: {
                                                 widgetMenu.activeSection = modelData.toLowerCase();
                                                 widgetMenu.refreshAudio();
                                             }
                                         }
                                     }
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
                              cardOn: widgetMenu.opened && widgetMenu.activeSection === "monitoreo"
                             visible: widgetMenu.activeSection === "monitoreo"

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
                             visible: root.hasBattery && widgetMenu.activeSection === "monitoreo"

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
                                if (!b)
                                    return 0;
                                const t = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.timeToEmpty;
                                if (b.energy > 0 && t > 0)
                                    return b.energy * 3600 / t;
                                return 0;
                            }

                            function stateText() {
                                const s = root.batt ? root.batt.state : -1;
                                switch (s) {
                                case UPowerDeviceState.Charging:
                                    return "Cargando";
                                case UPowerDeviceState.Discharging:
                                    return "Descargando";
                                case UPowerDeviceState.FullyCharged:
                                    return "Cargada";
                                case UPowerDeviceState.Empty:
                                    return "Vac\u00eda";
                                default:
                                    return "---";
                                }
                            }

                            function fmtEta(sec) {
                                if (!sec || sec <= 0)
                                    return "";
                                const h = Math.floor(sec / 3600);
                                const m = Math.round((sec % 3600) / 60);
                                if (h >= 100)
                                    return (h / 24).toFixed(0) + "d";
                                if (h > 0)
                                    return h + "h " + String(m).padStart(2, "0") + "m";
                                return m + "m";
                            }

                            function battSub() {
                                if (!root.hasBattery)
                                    return "---";
                                let s = battCard.stateText();
                                const w = battCard.watts();
                                if (w > 0)
                                    s += " \u00b7 " + w.toFixed(1) + "W";
                                const b = root.batt;
                                const t = b.state === UPowerDeviceState.Charging ? b.timeToFull : b.timeToEmpty;
                                const eta = battCard.fmtEta(t);
                                if (eta)
                                    s += " \u00b7 " + eta;
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
                             visible: root.hasBattery && widgetMenu.activeSection === "monitoreo"

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
                                running: root.hasBattery

                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: line => {
                                        let m = line.match(/Modo:\s*(\w+)/);
                                        if (m)
                                            gpuCard.modo = m[1];
                                        m = line.match(/Fuente:\s*(\w+)/);
                                        if (m)
                                            gpuCard.fuente = m[1];
                                    }
                                }
                            }

                            Timer {
                                interval: 5000
                                running: root.hasBattery
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

                          Rectangle {
                              id: audioCard
                              width: parent.width
                              height: audioDetailsOpen ? 70 + audioDetails.implicitHeight + 12 : 70
                              radius: 12
                              color: "#16161c"
                              border.color: "#26262e"
                              border.width: 1
                              visible: widgetMenu.activeSection === "dispositivos"

                              property bool audioDetailsOpen: true
                              property string audioMessage: ""
                              property var sinks: ListModel {}
                              property var sources: ListModel {}
                              property var cameras: ListModel {}

                              function parseAudio(line) {
                                  const parts = line.split("|");
                                  if (parts.length < 4)
                                      return;
                                  const item = { deviceId: parts[1], name: parts[2], selected: parts[3] === "*" };
                                  if (parts[0] === "sink")
                                      sinks.append(item);
                                  else if (parts[0] === "source")
                                      sources.append(item);
                              }

                              function parseCamera(line) {
                                  const parts = line.split("|");
                                  if (parts.length < 2)
                                      return;
                                  cameras.append({ device: parts[0], name: parts[1] || parts[0] });
                              }

                              function selectDevice(id, label) {
                                  audioSetDefault.command = ["wpctl", "set-default", id];
                                  audioCard.audioMessage = "Seleccionando " + label + "...";
                                  audioSetDefault.running = true;
                              }

                              RowLayout {
                                  anchors.fill: parent
                                  anchors.leftMargin: 14
                                  anchors.rightMargin: 14
                                  anchors.topMargin: 10
                                  anchors.bottomMargin: 10
                                  spacing: 10

                                  Text {
                                      text: "\uf028"
                                      color: "#cba6f7"
                                      font.family: root.fontFamily
                                      font.pixelSize: 24
                                      Layout.preferredWidth: 28
                                  }

                                  Column {
                                      spacing: 2
                                      Layout.fillWidth: true
                                      Text {
                                          text: "DISPOSITIVOS"
                                          color: "#9a9aa7"
                                          font.family: root.fontFamily
                                          font.pixelSize: 9
                                          font.letterSpacing: 1.5
                                      }
                                      Text {
                                          text: audioCard.sinks.count + " salidas · " + audioCard.sources.count + " entradas · " + audioCard.cameras.count + " cámaras"
                                          color: "white"
                                          font.family: root.fontFamily
                                          font.pixelSize: 14
                                      }
                                  }

                                  Text {
                                      text: "\uf078"
                                      color: "#9a9aa7"
                                      font.family: root.fontFamily
                                      font.pixelSize: 12
                                  }
                              }

                              MouseArea {
                                  anchors.fill: parent
                                  onClicked: audioCard.audioDetailsOpen = !audioCard.audioDetailsOpen
                              }

                              Column {
                                  id: audioDetails
                                  anchors.top: parent.top
                                  anchors.topMargin: 76
                                  anchors.left: parent.left
                                  anchors.right: parent.right
                                  anchors.leftMargin: 14
                                  anchors.rightMargin: 14
                                  spacing: 8
                                  visible: audioCard.audioDetailsOpen

                                  Text {
                                      text: "CÁMARAS"
                                      color: "#9a9aa7"
                                      font.family: root.fontFamily
                                      font.pixelSize: 9
                                      font.bold: true
                                  }

                                  Repeater {
                                      model: audioCard.cameras
                                      delegate: Rectangle {
                                          required property string device
                                          required property string name
                                          width: audioDetails.width
                                          height: 34
                                          radius: 8
                                          color: "#1d1d26"
                                          Text {
                                              anchors.left: parent.left
                                              anchors.leftMargin: 10
                                              anchors.right: parent.right
                                              anchors.rightMargin: 10
                                              anchors.verticalCenter: parent.verticalCenter
                                              text: "●  " + name + " (" + device + ")"
                                              color: "white"
                                              font.family: root.fontFamily
                                              font.pixelSize: 10
                                              elide: Text.ElideRight
                                          }
                                      }
                                  }

                                  Text {
                                      text: "SALIDAS"
                                      color: "#9a9aa7"
                                      font.family: root.fontFamily
                                      font.pixelSize: 9
                                      font.bold: true
                                  }

                                  Repeater {
                                      model: audioCard.sinks
                                      delegate: Rectangle {
                                          required property string deviceId
                                          required property string name
                                          required property bool selected
                                          width: audioDetails.width
                                          height: 34
                                          radius: 8
                                          color: audioDeviceArea.containsMouse ? "#252532" : selected ? "#29233b" : "#1d1d26"
                                          Text {
                                              anchors.left: parent.left
                                              anchors.leftMargin: 10
                                              anchors.right: parent.right
                                              anchors.rightMargin: 10
                                              anchors.verticalCenter: parent.verticalCenter
                                              text: (selected ? "●  " : "○  ") + name
                                              color: selected ? "#cba6f7" : "white"
                                              font.family: root.fontFamily
                                              font.pixelSize: 10
                                              elide: Text.ElideRight
                                          }
                                          MouseArea {
                                              id: audioDeviceArea
                                              anchors.fill: parent
                                              hoverEnabled: true
                                              onClicked: audioCard.selectDevice(deviceId, name)
                                          }
                                      }
                                  }

                                  Text {
                                      text: "ENTRADAS"
                                      color: "#9a9aa7"
                                      font.family: root.fontFamily
                                      font.pixelSize: 9
                                      font.bold: true
                                  }

                                  Repeater {
                                      model: audioCard.sources
                                      delegate: Rectangle {
                                          required property string deviceId
                                          required property string name
                                          required property bool selected
                                          width: audioDetails.width
                                          height: 34
                                          radius: 8
                                          color: audioInputArea.containsMouse ? "#252532" : selected ? "#29233b" : "#1d1d26"
                                          Text {
                                              anchors.left: parent.left
                                              anchors.leftMargin: 10
                                              anchors.right: parent.right
                                              anchors.rightMargin: 10
                                              anchors.verticalCenter: parent.verticalCenter
                                              text: (selected ? "●  " : "○  ") + name
                                              color: selected ? "#cba6f7" : "white"
                                              font.family: root.fontFamily
                                              font.pixelSize: 10
                                              elide: Text.ElideRight
                                          }
                                          MouseArea {
                                              id: audioInputArea
                                              anchors.fill: parent
                                              hoverEnabled: true
                                              onClicked: audioCard.selectDevice(deviceId, name)
                                          }
                                      }
                                  }

                                  Text {
                                      text: audioCard.audioMessage || "Selecciona dispositivo predeterminado"
                                      color: "#9a9aa7"
                                      font.family: root.fontFamily
                                      font.pixelSize: 10
                                      elide: Text.ElideRight
                                  }
                              }

                              Process {
                                  id: audioStatus
                                  command: ["bash", "-c", "wpctl status | awk '/^Audio$/{audio=1} /^Video$/{audio=0; s=\"\"} /Sinks:/ && audio{s=\"sink\"; next} /Sources:/ && audio{s=\"source\"; next} /Filters:/{s=\"\"; next} audio && s && match($0,/\\*?[[:space:]]*[0-9]+\\./){prefix=substr($0,RSTART,RLENGTH-1); star=(prefix ~ /\\*/ ? \"*\" : \"\"); gsub(/[^0-9]/,\"\",prefix); line=substr($0,RSTART+RLENGTH); sub(/^[[:space:]]+/,\"\",line); print s \"|\" prefix \"|\" line \"|\" star}'"]
                                  running: false
                                  stdout: SplitParser {
                                      splitMarker: "\n"
                                      onRead: line => audioCard.parseAudio(line)
                                  }
                                  onExited: audioCard.audioMessage = "Selecciona dispositivo predeterminado"
                              }

                              Process {
                                  id: audioSetDefault
                                  command: ["wpctl", "set-default", "0"]
                                  running: false
                                  onExited: {
                                      audioCard.audioMessage = exitCode === 0 ? "Dispositivo predeterminado actualizado" : "No se pudo seleccionar dispositivo";
                                      audioStatus.running = true;
                                  }
                              }

                              Process {
                                  id: cameraStatus
                                  command: ["bash", "-c", "for d in /dev/video*; do [ -e \"$d\" ] || continue; name=$(udevadm info -q property -n \"$d\" 2>/dev/null | awk -F= '/^ID_V4L_PRODUCT=/{print $2; exit}'); printf '%s|%s\\n' \"$d\" \"${name:-$d}\"; done"]
                                  running: false
                                  stdout: SplitParser {
                                      splitMarker: "\n"
                                      onRead: line => audioCard.parseCamera(line)
                                  }
                              }
                          }

                          Rectangle {
                             id: wifiCard
                             width: parent.width
                             height: wifiDetailsOpen ? 70 + wifiDetails.implicitHeight + 12 : 70
                             radius: 12
                             color: "#16161c"
                             border.color: "#26262e"
                             border.width: 1
                             visible: widgetMenu.activeSection === "conexiones"

                             Behavior on height {
                                 NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                             }

                            property bool wifiOn: false
                            property string network: "Sin conexión"
                            property bool wifiDetailsOpen: false
                            property string wifiMessage: ""
                            property string selectedSsid: ""
                             property string wifiPassword: ""
                             property bool wifiAdvancedOpen: false
                             property string wifiIdentity: ""
                             property string wifiAnonymousIdentity: ""
                             property string wifiEap: "peap"
                             property string wifiPhase2: "mschapv2"
                             property string wifiCaCert: ""
                             property string wifiClientCert: ""
                             property string wifiClientKey: ""
                             property string wifiDomain: ""
                             property var wifiNetworks: ListModel {}

                            function refreshNetworks() {
                                wifiCard.wifiMessage = "Buscando redes...";
                                wifiCard.wifiNetworks.clear();
                                wifiScan.running = false;
                                wifiScan.running = true;
                            }

                             function parseNetwork(line) {
                                const match = line.trim().match(/^(.*):([0-9]+):(.*)$/);
                                if (!match || !match[1])
                                    return;
                                const ssid = match[1].replace(/\\\\:/g, ":").replace(/\\\\\\\\/g, "\\\\");
                                const signal = match[2];
                                const security = match[3];
                                for (let i = 0; i < wifiCard.wifiNetworks.count; i++) {
                                    if (wifiCard.wifiNetworks.get(i).ssid === ssid)
                                        return;
                                }
                                wifiCard.wifiNetworks.append({
                                    ssid: ssid,
                                    signal: signal,
                                    security: security || "Abierta"
                                 });
                             }

                             function connectCommand() {
                                 let args = ["nmcli", "dev", "wifi", "connect", wifiCard.selectedSsid];
                                 if (wifiCard.wifiPassword)
                                     args.push("password", wifiCard.wifiPassword);
                                 if (wifiCard.wifiAdvancedOpen && wifiCard.wifiIdentity) {
                                     args.push("wifi-sec.key-mgmt", "wpa-eap");
                                     args.push("802-1x.identity", wifiCard.wifiIdentity);
                                     args.push("802-1x.eap", wifiCard.wifiEap || "peap");
                                     args.push("802-1x.phase2-auth", wifiCard.wifiPhase2 || "mschapv2");
                                     if (wifiCard.wifiAnonymousIdentity)
                                         args.push("802-1x.anonymous-identity", wifiCard.wifiAnonymousIdentity);
                                     if (wifiCard.wifiCaCert)
                                         args.push("802-1x.ca-cert", wifiCard.wifiCaCert);
                                     if (wifiCard.wifiClientCert)
                                         args.push("802-1x.client-cert", wifiCard.wifiClientCert);
                                     if (wifiCard.wifiClientKey)
                                         args.push("802-1x.private-key", wifiCard.wifiClientKey);
                                     if (wifiCard.wifiDomain)
                                         args.push("802-1x.domain", wifiCard.wifiDomain);
                                 }
                                 return args;
                             }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 10
                                 height: 58
                                spacing: 10

                                Text {
                                    text: wifiCard.wifiOn ? "\uf1eb" : "\uf127"
                                    color: wifiCard.wifiOn ? "#89b4fa" : "#6c7086"
                                    font.family: root.fontFamily
                                     font.pixelSize: 24
                                    Layout.preferredWidth: 28
                                }

                                Column {
                                    spacing: 2

                                    Text {
                                        text: "WI-FI"
                                        color: "#9a9aa7"
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.5
                                    }

                                    Text {
                                        text: wifiCard.wifiOn ? wifiCard.network : "Desactivado"
                                        color: "white"
                                        font.family: root.fontFamily
                                         font.pixelSize: 17
                                        elide: Text.ElideRight
                                         width: 245
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: wifiCard.wifiDetailsOpen = !wifiCard.wifiDetailsOpen
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    width: 48
                                     height: 30
                                     radius: 9
                                    color: wifiToggleArea.containsMouse ? "#89b4fa" : "#262633"

                                    Text {
                                        anchors.centerIn: parent
                                        text: wifiCard.wifiOn ? "ON" : "OFF"
                                        color: wifiToggleArea.containsMouse ? "#11111b" : "#cdd6f4"
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: wifiToggleArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            wifiToggle.running = false;
                                            wifiToggle.running = true;
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.bottomMargin: parent.height - 78
                                anchors.rightMargin: 62
                                z: 1
                                onClicked: wifiCard.wifiDetailsOpen = !wifiCard.wifiDetailsOpen
                            }

                            Column {
                                id: wifiDetails
                                anchors.top: parent.top
                                anchors.topMargin: 84
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 9
                                visible: wifiCard.wifiDetailsOpen
                                opacity: wifiCard.wifiDetailsOpen ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }

                                      RowLayout {
                                          width: parent.width
                                          spacing: 6

                                    TextInput {
                                        id: wifiPasswordInput
                                        Layout.fillWidth: true
                                         height: 34
                                        color: "white"
                                        text: wifiCard.wifiPassword
                                        font.family: root.fontFamily
                                        font.pixelSize: 11
                                        echoMode: TextInput.Password
                                        padding: 7
                                        selectByMouse: true
                                        clip: true
                                        onTextChanged: wifiCard.wifiPassword = text
                                        Rectangle {
                                            anchors.fill: parent
                                            z: -1
                                             radius: 8
                                            color: "#0d0d12"
                                            border.color: "#30303b"
                                        }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Contraseña"
                                            color: "#6c7086"
                                            font.family: root.fontFamily
                                            font.pixelSize: 11
                                            visible: !wifiPasswordInput.text
                                        }
                                    }

                                    Rectangle {
                                         width: 96
                                         height: 34
                                         radius: 8
                                        color: wifiRefreshArea.containsMouse ? "#89b4fa" : "#262633"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "ESCANEAR"
                                            color: wifiRefreshArea.containsMouse ? "#11111b" : "#cdd6f4"
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: wifiRefreshArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: wifiCard.refreshNetworks()
                                          }
                                      }

                                   }

                                 Rectangle {
                                     width: parent.width
                                     height: 32
                                     radius: 8
                                     color: wifiCard.wifiAdvancedOpen ? "#89b4fa" : wifiAdvancedArea.containsMouse ? "#262633" : "#1d1d26"
                                     Text {
                                         anchors.centerIn: parent
                                         text: wifiCard.wifiAdvancedOpen ? "OCULTAR OPCIONES AVANZADAS" : "OPCIONES AVANZADAS (802.1X / UNIVERSIDAD)"
                                         color: wifiCard.wifiAdvancedOpen ? "#11111b" : "#cdd6f4"
                                         font.family: root.fontFamily
                                         font.pixelSize: 9
                                         font.bold: true
                                     }
                                     MouseArea {
                                         id: wifiAdvancedArea
                                         anchors.fill: parent
                                         hoverEnabled: true
                                         onClicked: wifiCard.wifiAdvancedOpen = !wifiCard.wifiAdvancedOpen
                                     }
                                 }

                                 Column {
                                     width: parent.width
                                     spacing: 6
                                     visible: wifiCard.wifiAdvancedOpen

                                     Text {
                                         text: "WPA-ENTERPRISE / 802.1X"
                                         color: "#9a9aa7"
                                         font.family: root.fontFamily
                                         font.pixelSize: 9
                                         font.bold: true
                                     }

                                     RowLayout {
                                         width: parent.width
                                         spacing: 6
                                         TextInput {
                                             Layout.fillWidth: true
                                             height: 32
                                             color: "white"
                                             text: wifiCard.wifiIdentity
                                             font.family: root.fontFamily
                                             font.pixelSize: 10
                                             padding: 7
                                             onTextChanged: wifiCard.wifiIdentity = text
                                             Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                             Text { anchors.fill: parent; anchors.margins: 7; text: "Usuario / identidad"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                         }
                                         TextInput {
                                             Layout.fillWidth: true
                                             height: 32
                                             color: "white"
                                             text: wifiCard.wifiEap
                                             font.family: root.fontFamily
                                             font.pixelSize: 10
                                             padding: 7
                                             onTextChanged: wifiCard.wifiEap = text
                                             Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                             Text { anchors.fill: parent; anchors.margins: 7; text: "EAP: peap / tls"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                         }
                                     }

                                     RowLayout {
                                         width: parent.width
                                         spacing: 6
                                         TextInput {
                                             Layout.fillWidth: true
                                             height: 32
                                             color: "white"
                                             text: wifiCard.wifiPhase2
                                             font.family: root.fontFamily
                                             font.pixelSize: 10
                                             padding: 7
                                             onTextChanged: wifiCard.wifiPhase2 = text
                                             Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                             Text { anchors.fill: parent; anchors.margins: 7; text: "Fase 2: mschapv2"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                         }
                                         TextInput {
                                             Layout.fillWidth: true
                                             height: 32
                                             color: "white"
                                             text: wifiCard.wifiAnonymousIdentity
                                             font.family: root.fontFamily
                                             font.pixelSize: 10
                                             padding: 7
                                             onTextChanged: wifiCard.wifiAnonymousIdentity = text
                                             Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                             Text { anchors.fill: parent; anchors.margins: 7; text: "Identidad anónima (opcional)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                         }
                                     }

                                     RowLayout {
                                         width: parent.width
                                         spacing: 6
                                         TextInput {
                                             Layout.fillWidth: true
                                             height: 32
                                             color: "white"
                                             text: wifiCard.wifiCaCert
                                             font.family: root.fontFamily
                                             font.pixelSize: 10
                                             padding: 7
                                             onTextChanged: wifiCard.wifiCaCert = text
                                             Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                             Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado CA (opcional)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                         }
                                         TextInput {
                                             Layout.fillWidth: true
                                             height: 32
                                             color: "white"
                                             text: wifiCard.wifiDomain
                                             font.family: root.fontFamily
                                             font.pixelSize: 10
                                             padding: 7
                                             onTextChanged: wifiCard.wifiDomain = text
                                             Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                              Text { anchors.fill: parent; anchors.margins: 7; text: "Dominio (opcional)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                          }
                                      }

                                      RowLayout {
                                          width: parent.width
                                          spacing: 6
                                          TextInput {
                                              Layout.fillWidth: true
                                              height: 32
                                              color: "white"
                                              text: wifiCard.wifiClientCert
                                              font.family: root.fontFamily
                                              font.pixelSize: 10
                                              padding: 7
                                              onTextChanged: wifiCard.wifiClientCert = text
                                              Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                              Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado cliente (EAP-TLS)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                          }
                                          TextInput {
                                              Layout.fillWidth: true
                                              height: 32
                                              color: "white"
                                              text: wifiCard.wifiClientKey
                                              font.family: root.fontFamily
                                              font.pixelSize: 10
                                              padding: 7
                                              onTextChanged: wifiCard.wifiClientKey = text
                                              Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                              Text { anchors.fill: parent; anchors.margins: 7; text: "Clave privada (EAP-TLS)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                          }
                                      }
                                  }

                                 ListView {
                                    width: parent.width
                                     height: Math.min(contentHeight, 190)
                                    visible: count > 0
                                    clip: true
                                    model: wifiCard.wifiNetworks
                                    spacing: 3
                                    delegate: Rectangle {
                                        required property string ssid
                                        required property string signal
                                        required property string security
                                        width: wifiDetails.width
                                         height: 34
                                         radius: 7
                                        color: wifiNetworkArea.containsMouse ? "#252532" : "#1d1d26"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            Text {
                                                Layout.fillWidth: true
                                                text: ssid + "  " + signal + "%"
                                                color: "white"
                                                font.family: root.fontFamily
                                                 font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: security
                                                color: "#9a9aa7"
                                                font.family: root.fontFamily
                                                font.pixelSize: 9
                                            }
                                        }
                                        MouseArea {
                                            id: wifiNetworkArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                wifiCard.selectedSsid = ssid;
                                                wifiCard.wifiMessage = ssid + " seleccionado";
                                            }
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: wifiCard.wifiNetworks.count ? wifiCard.wifiMessage : (wifiCard.wifiMessage || "Buscando redes...")
                                    color: "#9a9aa7"
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 34
                                    radius: 8
                                    color: wifiConnectArea.containsMouse ? "#89b4fa" : "#262633"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "CONECTAR" + (wifiCard.selectedSsid ? " · " + wifiCard.selectedSsid : "")
                                        color: wifiConnectArea.containsMouse ? "#11111b" : "#cdd6f4"
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width - 12
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        id: wifiConnectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (!wifiCard.selectedSsid)
                                                return;
                                             wifiConnect.command = wifiCard.connectCommand();
                                            wifiCard.wifiMessage = "Conectando...";
                                            wifiConnect.running = false;
                                            wifiConnect.running = true;
                                        }
                                    }
                                }
                            }

                            Process {
                                id: wifiScan
                                command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: line => wifiCard.parseNetwork(line)
                                }
                                onExited: wifiCard.wifiMessage = wifiCard.wifiNetworks.count ? "Selecciona una red" : "nmcli no disponible o sin redes"
                            }

                            Process {
                                id: wifiConnect
                                command: ["nmcli", "dev", "wifi", "connect", ""]
                                running: false
                                onExited: {
                                    wifiCard.wifiMessage = exitCode === 0 ? "Conectado" : "No se pudo conectar";
                                    wifiStatus.running = false;
                                    wifiStatus.running = true;
                                }
                            }

                            Process {
                                id: wifiStatus
                                 command: ["bash", "-c", "enabled=$(nmcli -t -f WIFI g | head -n1); network=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1==\"yes\"{sub(/^yes:/,\"\"); print; exit}'); wired=$(nmcli -t -f TYPE,STATE,CONNECTION dev | awk -F: '$1==\"ethernet\" && $2==\"connected\"{print $3; exit}'); printf '%s|%s|%s' \"$enabled\" \"$network\" \"$wired\""]
                                running: true

                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        const parts = this.text.trim().split("|");
                                        wifiCard.wifiOn = parts[0] === "enabled";
                                         wifiCard.network = parts[1] || (parts[2] ? "Cable: " + parts[2] : "Sin conexión");
                                    }
                                }
                            }

                            Process {
                                id: wifiToggle
                                command: ["nmcli", "radio", "wifi", "toggle"]
                                running: false

                                onExited: {
                                    wifiStatus.running = false;
                                    wifiStatus.running = true;
                                }
                            }

                            Timer {
                                interval: 20000
                                running: true
                                repeat: true
                                onTriggered: {
                                    wifiStatus.running = true;
                                    widgetMenu.refreshConnections();
                                }
                            }
                        }

                         Rectangle {
                             id: bluetoothCard
                            width: parent.width
                            height: btDetailsOpen ? 70 + btDetails.implicitHeight + 12 : 70
                            radius: 12
                            color: "#16161c"
                            border.color: "#26262e"
                             border.width: 1
                             visible: widgetMenu.activeSection === "conexiones"

                             Behavior on height {
                                 NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                             }

                            property bool btOn: false
                            property string stateText: "No disponible"
                            property bool btDetailsOpen: false
                            property string btMessage: ""
                            property string selectedMac: ""
                            property var btDevices: ListModel {}

                            function refreshDevices() {
                                btMessage = "Buscando dispositivos...";
                                btDevices.clear();
                                btScan.running = false;
                                btScan.running = true;
                            }

                            function parseDevice(line) {
                                 const match = line.trim().match(/^Device\s+([^ ]+)\s+(.+)$/);
                                if (!match)
                                    return;
                                for (let i = 0; i < btDevices.count; i++) {
                                    if (btDevices.get(i).mac === match[1])
                                        return;
                                }
                                btDevices.append({
                                    mac: match[1],
                                    name: match[2]
                                });
                            }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 10
                                 height: 58
                                spacing: 10

                                Text {
                                    text: "\uf294"
                                    color: bluetoothCard.btOn ? "#89dceb" : "#6c7086"
                                    font.family: root.fontFamily
                                     font.pixelSize: 24
                                    Layout.preferredWidth: 28
                                }

                                Column {
                                    spacing: 2

                                    Text {
                                        text: "BLUETOOTH"
                                        color: "#9a9aa7"
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.5
                                    }

                                    Text {
                                        text: bluetoothCard.stateText
                                        color: "white"
                                        font.family: root.fontFamily
                                         font.pixelSize: 17
                                        elide: Text.ElideRight
                                         width: 245
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: bluetoothCard.btDetailsOpen = !bluetoothCard.btDetailsOpen
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    width: 48
                                    height: 30
                                    radius: 9
                                    color: btToggleArea.containsMouse ? "#89dceb" : "#262633"

                                    Text {
                                        anchors.centerIn: parent
                                        text: bluetoothCard.btOn ? "ON" : "OFF"
                                        color: btToggleArea.containsMouse ? "#11111b" : "#cdd6f4"
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: btToggleArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            bluetoothToggle.running = false;
                                            bluetoothToggle.running = true;
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.bottomMargin: parent.height - 78
                                anchors.rightMargin: 62
                                z: 1
                                onClicked: bluetoothCard.btDetailsOpen = !bluetoothCard.btDetailsOpen
                            }

                            Column {
                                id: btDetails
                                anchors.top: parent.top
                                anchors.topMargin: 84
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 9
                                visible: bluetoothCard.btDetailsOpen
                                opacity: bluetoothCard.btDetailsOpen ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }

                                Rectangle {
                                    width: parent.width
                                     height: 34
                                     radius: 8
                                    color: btRefreshArea.containsMouse ? "#89dceb" : "#262633"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "ESCANEAR BLUETOOTH"
                                        color: btRefreshArea.containsMouse ? "#11111b" : "#cdd6f4"
                                        font.family: root.fontFamily
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                    MouseArea {
                                        id: btRefreshArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: bluetoothCard.refreshDevices()
                                    }
                                }

                                ListView {
                                    width: parent.width
                                    height: Math.min(contentHeight, 190)
                                    visible: count > 0
                                    clip: true
                                    model: bluetoothCard.btDevices
                                    spacing: 3
                                    delegate: Rectangle {
                                        required property string mac
                                        required property string name
                                        width: btDetails.width
                                         height: 54
                                         radius: 7
                                        color: btDeviceArea.containsMouse ? "#252532" : "#1d1d26"
                                        Column {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Text {
                                                text: name
                                                color: "white"
                                                font.family: root.fontFamily
                                                 font.pixelSize: 11
                                                elide: Text.ElideRight
                                                width: btDetails.width - 16
                                            }
                                            Text {
                                                text: mac
                                                color: "#9a9aa7"
                                                font.family: root.fontFamily
                                                font.pixelSize: 9
                                            }
                                        }
                                        MouseArea {
                                            id: btDeviceArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                bluetoothCard.selectedMac = mac;
                                                bluetoothCard.btMessage = name + " seleccionado";
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 4
                                    Repeater {
                                         model: ["PAIR", "TRUST", "CONNECT", "DISCONNECT", "FORGET"]
                                        delegate: Rectangle {
                                            required property string modelData
                                            Layout.fillWidth: true
                                    height: 34
                                    radius: 8
                                            color: btActionArea.containsMouse ? "#89dceb" : "#262633"
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: btActionArea.containsMouse ? "#11111b" : "#cdd6f4"
                                                font.family: root.fontFamily
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                            MouseArea {
                                                id: btActionArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    if (!bluetoothCard.selectedMac)
                                                        return;
                                                     bluetoothAction.routeAudio = modelData === "CONNECT";
                                                     bluetoothAction.command = bluetoothAction.routeAudio ? ["bash", "-c", "bluetoothctl connect \"" + bluetoothCard.selectedMac + "\" && sleep 1"] : ["bluetoothctl", modelData === "FORGET" ? "remove" : modelData.toLowerCase(), bluetoothCard.selectedMac];
                                                    bluetoothCard.btMessage = modelData.toLowerCase() + "...";
                                                     bluetoothAction.running = false;
                                                     bluetoothAction.running = true;
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: bluetoothCard.btDevices.count ? bluetoothCard.btMessage : (bluetoothCard.btMessage || "Buscando dispositivos...")
                                    color: "#9a9aa7"
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }
                            }

                            Process {
                                id: btScan
                                command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
                                running: false
                                onExited: {
                                    btList.running = false;
                                    btList.running = true;
                                }
                            }

                            Process {
                                id: btList
                                command: ["bluetoothctl", "devices"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: line => bluetoothCard.parseDevice(line)
                                }
                                onExited: bluetoothCard.btMessage = bluetoothCard.btDevices.count ? "Selecciona un dispositivo" : "bluetoothctl no disponible o sin dispositivos"
                            }

                            Process {
                                id: bluetoothAction
                                command: ["bluetoothctl", "connect", ""]
                                running: false
                                property bool routeAudio: false
                                onExited: {
                                    if (routeAudio && exitCode === 0) {
                                        bluetoothAudioRoute.command = ["bash", "-c", "mac=\"" + bluetoothCard.selectedMac + "\"; sink=$(wpctl status | awk '/Sinks:/{s=1; next} /Sources:/{s=0} s && /[0-9]+\\./{match($0, /[0-9]+\\./); print substr($0, RSTART, RLENGTH - 1)}' | while read id; do wpctl inspect \"$id\" | awk -v mac=\"$mac\" -v sink_id=\"$id\" '$0 ~ mac{found=1} END{if(found) print sink_id}'; done | head -n1); [ -n \"$sink\" ] && wpctl set-default \"$sink\""];
                                        bluetoothAudioRoute.running = false;
                                        bluetoothAudioRoute.running = true;
                                    } else {
                                        bluetoothCard.btMessage = exitCode === 0 ? "Acción completada" : "Acción fallida";
                                        bluetoothStatus.running = false;
                                        bluetoothStatus.running = true;
                                    }
                                }
                            }

                            Process {
                                id: bluetoothAudioRoute
                                command: ["true"]
                                running: false
                                onExited: {
                                    bluetoothCard.btMessage = exitCode === 0 ? "Audio conectado" : "Audio no disponible";
                                    bluetoothStatus.running = false;
                                    bluetoothStatus.running = true;
                                }
                            }

                            Process {
                                id: bluetoothStatus
                                 command: ["bash", "-c", "powered=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'); device=$(bluetoothctl devices Connected 2>/dev/null | awk 'NR==1{sub(/^Device [^ ]+ /,\"\"); print}'); printf '%s|%s' \"$powered\" \"$device\""]
                                running: true

                                 stdout: StdioCollector {
                                     onStreamFinished: {
                                         const parts = this.text.trim().split("|");
                                         const powered = parts[0] === "yes";
                                         bluetoothCard.btOn = powered;
                                          bluetoothCard.stateText = powered ? (parts[1] || "Activado") : "Desactivado";
                                     }
                                }
                            }

                            Process {
                                id: bluetoothToggle
                                command: ["bash", "-c", "powered=$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'); bluetoothctl power $([[ \"$powered\" == \"yes\" ]] && echo off || echo on)"]
                                running: false

                                onExited: {
                                    bluetoothStatus.running = false;
                                    bluetoothStatus.running = true;
                                }
                            }

                            Timer {
                                interval: 20000
                                running: true
                                repeat: true
                                onTriggered: {
                                    bluetoothStatus.running = true;
                                    widgetMenu.refreshConnections();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
