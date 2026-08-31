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
    property int expandedHeight: 40
    property int hotEdge: 3

    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBattery: batt != null && batt.isPresent && batt.type === UPowerDeviceType.Battery
    readonly property double battPct: root.hasBattery ? root.batt.percentage * 100 : 0
    property double volumePct: 0
    property bool volumeMuted: false
    property double brightnessPct: 0
    property int kbIndex: 0
    property string powerProfile: ""
    property bool syncActive: false
    readonly property var kbLabels: ["DV", "ES", "US"]
    property var audioSinks: ListModel {}
    property var audioSources: ListModel {}
    property string clockFull: ""

    // ── Modo juegos ──
    property bool gameModeActive: false   // expande root a fullscreen
    property bool gameShown: false        // fase de fade-in del overlay
    property bool gameClosing: false      // fase de fade-out
    property bool gameLaunching: false    // lanzando cartridges/steam
    property bool gameArmed: false        // modo activo (Cartridges corriendo)

    function resetHover(area) {
        if (area.hov !== undefined)
            area.hov = false;
    }

    function scanAudioDevices() {
        audioSinks.clear();
        audioSources.clear();
        audioStatus.running = false;
        audioStatus.running = true;
    }

    function setDefaultDevice(id) {
        audioSetDefault.command = ["wpctl", "set-default", id];
        audioSetDefault.running = false;
        audioSetDefault.running = true;
    }

    function gameEnter() {
        root.gameShown = true;
        root.gameClosing = false;
        root.gameModeActive = true;
    }
    function gameCancel() {
        if (!root.gameModeActive) return;
        root.gameClosing = true;
        gameModeHide.restart();
    }
    function gameGo() {
        root.gameLaunching = true;
        gameLaunch.running = true;
    }
    function gameConfirmClose() {
        gameLaunch.command = ["game-mode.sh"];
        gameGo();
    }
    function gameConfirmNoClose() {
        gameLaunch.command = ["game-mode.sh", "noclose"];
        gameGo();
    }
    function gameExit() {
        gameExitProc.running = true;
        root.gameArmed = false;
        root.gameCancel();
    }
    function gameToggle() {
        if (root.gameModeActive) root.gameCancel();
        else root.gameEnter();
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Normal

    anchors {
        top: true
        left: true
        right: true
        bottom: root.gameModeActive
    }

    readonly property bool expanded: hot.hovered || superHeld || widgetMenu.opened || powerMenu.opened || volumeMenu.opened || ramMenu.opened || dateMenu.opened

    implicitHeight: expanded ? expandedHeight : hotEdge
    exclusiveZone: root.gameModeActive ? 2000 : implicitHeight
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

    // Monitor de volante (botón PS, BTN_MODE): emite "1" → toglea modo juegos.
    Process {
        id: wheelMonitor
        command: ["wheel-mode-monitor.sh"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data === "1")
                    root.gameToggle();
            }
        }
    }

    Timer {
        id: gameModeHide
        interval: 240
        onTriggered: {
            root.gameModeActive = false;
            root.gameShown = false;
            root.gameClosing = false;
            root.gameLaunching = false;
        }
    }

    Process {
        id: gameLaunch
        command: ["true"]
        running: false
        onExited: {
            root.gameArmed = true;
            gameModeHide.restart();
        }
    }

    Process {
        id: gameExitProc
        command: ["game-mode.sh", "exit"]
        running: false
    }

    Process {
        id: volumeStatus
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf \"%s %s\", $2 * 100, ($3 == \"[MUTED]\" ? \"yes\" : \"no\")}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split(/\s+/);
                root.volumePct = parseFloat(p[0]) || 0;
                root.volumeMuted = p[1] === "yes";
                if (!volumeInput.activeFocus)
                    volumeInput.text = Math.round(root.volumePct).toString();
            }
        }
    }

    Process {
        id: kbStatus
        command: ["bash", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .active_keymap'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.trim();
                if (!m)
                    return;
                root.kbIndex = /dvorak|programador/i.test(m) ? 0 : /spanish|espa\u00f1ol/i.test(m) ? 1 : 2;
            }
        }
    }

    Process {
        id: kbSwitch
        command: ["true"]
        running: false
        onExited: {
            kbStatus.running = false;
            kbStatus.running = true;
        }
    }

    Process {
        id: audioStatus
        command: ["bash", "-c", "wpctl status | awk '/^Audio$/{audio=1} /^Video$/{audio=0; s=\"\"} /Sinks:/ && audio{s=\"sink\"; next} /Sources:/ && audio{s=\"source\"; next} /Filters:/{s=\"\"; next} audio && s && match($0,/\\*?[[:space:]]*[0-9]+\\./){prefix=substr($0,RSTART,RLENGTH-1); star=(prefix ~ /\\*/ ? \"*\" : \"\"); gsub(/[^0-9]/,\"\",prefix); line=substr($0,RSTART+RLENGTH); sub(/^[[:space:]]+/,\"\",line); print s \"|\" prefix \"|\" line \"|\" star}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                for (const line of lines) {
                    const p = line.split("|");
                    if (p.length < 4)
                        continue;
                    const item = { deviceId: p[1], name: p[2], selected: p[3] === "*" };
                    if (p[0] === "sink")
                        root.audioSinks.append(item);
                    else if (p[0] === "source")
                        root.audioSources.append(item);
                }
            }
        }
    }

    Process {
        id: audioSetDefault
        command: ["wpctl", "set-default", "0"]
        running: false
        onExited: {
            audioCard.audioMessage = exitCode === 0 ? "Dispositivo predeterminado actualizado" : "No se pudo seleccionar dispositivo";
            root.scanAudioDevices();
        }
    }

    Process {
        id: brightnessStatus
        command: ["bash", "-c", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,\"\",$4); print $4}'"]
        running: root.hasBattery
        stdout: StdioCollector {
            onStreamFinished: root.brightnessPct = parseFloat(this.text.trim()) || 0
        }
    }

    Process {
        id: brightnessAdjust
        command: ["brightnessctl", "set", "5%+"]
        running: false
        onExited: brightnessStatus.running = true
    }

    Process {
        id: powerProfileStatus
        command: ["powerprofilesctl", "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.powerProfile = this.text.trim()
        }
    }

    Process {
        id: powerProfileSet
        command: ["powerprofilesctl", "set", "balanced"]
        running: false
        onExited: {
            powerProfileStatus.running = false;
            powerProfileStatus.running = true;
        }
    }

    Process {
        id: syncStatus
        command: ["systemctl", "is-active", "syncthing.service"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.syncActive = this.text.trim() === "active"
        }
    }

    Process {
        id: syncToggle
        command: ["true"]
        running: false
        onExited: syncStatus.running = true
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            volumeStatus.running = true;
            syncStatus.running = true;
            if (root.hasBattery) brightnessStatus.running = true;
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
        Text {
            id: clock
            anchors.centerIn: parent
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 12
        }

        MouseArea {
            id: clockArea
            anchors.fill: clock
            z: 2
            hoverEnabled: true
            onClicked: dateMenu.opened = !dateMenu.opened
        }

        Rectangle {
            anchors.fill: ramRow
            radius: 8
            color: ramArea.hov || ramMenu.opened ? "#5D3FD3" : "#141414"
        }

        Process {
            id: runDate
            command: ["date", "+%d %b · %H:%M"]
            running: true

            stdout: StdioCollector {
                onStreamFinished: clock.text = this.text.trim()
            }
        }

        Process {
            id: runDateFull
            command: ["date", "+%A %d de %B %Y %H:%M:%S %Z"]
            running: true

            stdout: StdioCollector {
                onStreamFinished: root.clockFull = this.text.trim()
            }
        }

        Timer {
            interval: 1000
             running: true
             repeat: true
            onTriggered: { runDate.running = true; runDateFull.running = true; }
        }
        Item {
            id: ramRow
            width: 64
            height: 22
            anchors.right: root.hasBattery ? batteryRow.left : menuRow.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    id: ramIcon
                    text: "\uf538"
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                }

                Text {
                    id: ramText
                    property double p: NaN
                    text: "--%"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: ramText.p > 90 ? "#e06c75" : "white"
                }
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
        MouseArea {
            id: ramArea
            property bool hov: false
            anchors.fill: ramRow
            z: 2
            hoverEnabled: true
            onEntered: hov = true
            onExited: hov = false
            onClicked: ramMenu.opened = !ramMenu.opened
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
                font.pixelSize: 15
            }

            Text {
                id: batteryText
                text: Math.round(root.battPct) + "%"
                font.family: root.fontFamily
                font.pixelSize: 14
                color: root.battPct <= 20 ? "#e06c75" : root.batt.state === UPowerDeviceState.Charging ? "#98c379" : "white"
            }

        }
        MouseArea {
            anchors.fill: batteryRow
            z: 2
            onClicked: {
                powerMenu.pendingAction = "";
                powerMenu.opened = !powerMenu.opened;
            }
        }
            Row {
                id: menuRow
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                    id: brightnessIndicator
                    visible: root.hasBattery
                    width: 60
                    height: 22
                    radius: 8
                    color: brightnessArea.containsMouse ? "#5D3FD3" : "#141414"
                    Text { anchors.centerIn: parent; text: "\uf185 " + Math.round(root.brightnessPct) + "%"; color: brightnessArea.containsMouse ? "#11111b" : "white"; font.family: root.fontFamily; font.pixelSize: 12 }
                    MouseArea {
                        id: brightnessArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onWheel: wheel => { brightnessAdjust.command = ["brightnessctl", wheel.angleDelta.y > 0 ? "set" : "set", wheel.angleDelta.y > 0 ? "5%+" : "5%-"]; brightnessAdjust.running = true; }
                    }
                }

                Rectangle {
                    id: volumeIndicator
                    width: 62
                    height: 22
                    radius: 8
                    color: volumeArea.hov || volumeMenu.opened ? "#5D3FD3" : "#141414"
                    Text { anchors.centerIn: parent; text: root.volumeMuted ? "\uf026" : "\uf028 " + Math.round(root.volumePct) + "%"; color: "white"; font.family: root.fontFamily; font.pixelSize: 12 }
                    MouseArea {
                        id: volumeArea
                        property bool hov: false
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hov = true
                        onExited: hov = false
                        onClicked: volumeMenu.opened = !volumeMenu.opened
                        onWheel: wheel => { volumeAdjust.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", wheel.angleDelta.y > 0 ? "5%+" : "5%-"]; volumeAdjust.running = true; }
                    }
                }

                Rectangle {
                    id: ccBtn
                    width: 32
                    height: 22
                    radius: 8
                    color: controlCenter.opened ? "#cba6f7" : ccArea.hov ? "#5D3FD3" : "#141414"

                    Text {
                        anchors.centerIn: parent
                        text: "\uf137"
                        color: "white"
                        font.family: root.fontFamily
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: ccArea
                        property bool hov: false
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hov = true
                        onExited: hov = false
                        onClicked: controlCenter.opened = !controlCenter.opened
                    }
                }

                Rectangle {
                    id: menuBtn
                    width: 32
                    height: 22
                    radius: 8
                    color: widgetMenu.opened ? "#cba6f7" : menuBtnArea.hov ? "#5D3FD3" : "#141414"

                    Text {
                        anchors.centerIn: parent
                        text: "\uf009"
                        color: "white"
                        font.family: root.fontFamily
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: menuBtnArea
                        property bool hov: false
                        hoverEnabled: true
                        anchors.fill: parent
                        onEntered: hov = true
                        onExited: hov = false
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

                }
            }
        }

        PopupWindow {
            id: controlCenter
            implicitWidth: 200
            implicitHeight: ccCol.implicitHeight + 32
            visible: opened
            grabFocus: true
            color: "transparent"
            property bool opened: false
            anchor { window: root; rect.x: root.width - controlCenter.implicitWidth - 12; rect.y: root.height + 8 }
            onOpenedChanged: if (!opened) root.resetHover(ccArea)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 14
                color: "#e60d0d12"
                border.color: "#383847"
                border.width: 1

                Column {
                    id: ccCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Text { text: "CONTROL"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2 }

                    Rectangle {
                        width: parent.width; height: 30; radius: 8
                        color: syncCcArea.containsMouse ? "#252532" : "#1d1d26"
                        Row { anchors.centerIn: parent; spacing: 8
                            Text { text: root.syncActive ? "\uf0c1" : "\uf127"; color: root.syncActive ? "#98c379" : "#6c7086"; font.family: root.fontFamily; font.pixelSize: 13 }
                            Text { text: "Syncthing"; color: root.syncActive ? "#98c379" : "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 11 }
                        }
                        MouseArea { id: syncCcArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                const stop = root.syncActive;
                                syncToggle.command = ["bash", "-c",
                                    stop ? "touch /tmp/syncthing-manual-off; sudo systemctl stop syncthing.service"
                                         : "rm -f /tmp/syncthing-manual-off; sudo systemctl start syncthing.service"];
                                syncToggle.running = false; syncToggle.running = true;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 30; radius: 8
                        color: kbdCcArea.containsMouse ? "#252532" : "#1d1d26"
                        Row { anchors.centerIn: parent; spacing: 8
                            Text { text: "\uf11c"; color: "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 13 }
                            Text { text: root.kbLabels[root.kbIndex]; color: "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 11; font.bold: true }
                        }
                        MouseArea { id: kbdCcArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                const next = (root.kbIndex + 1) % root.kbLabels.length;
                                kbSwitch.command = ["bash", "-c", "for k in $(hyprctl devices -j | jq -r '.keyboards[].name'); do hyprctl switchxkblayout \"$k\" " + next + " >/dev/null 2>&1; done"];
                                kbSwitch.running = false; kbSwitch.running = true;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 30; radius: 8
                        color: powerCcArea.containsMouse ? "#252532" : "#1d1d26"
                        Row { anchors.centerIn: parent; spacing: 8
                            Text { text: "\uf011"; color: "#f38ba8"; font.family: root.fontFamily; font.pixelSize: 13 }
                            Text { text: "Energia"; color: "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 11 }
                        }
                        MouseArea { id: powerCcArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: { controlCenter.opened = false; powerMenu.pendingAction = ""; powerMenu.opened = true; }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 30; radius: 8
                        color: gameCcArea.containsMouse ? "#252532" : "#1d1d26"
                        Row { anchors.centerIn: parent; spacing: 8
                            Text { text: "\uf11b"; color: root.gameArmed ? "#98c379" : root.gameModeActive ? "#cba6f7" : "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 13 }
                            Text { text: root.gameArmed ? "Jugando" : root.gameModeActive ? "Modo juego" : "Modo juegos"; color: "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 11 }
                        }
                        MouseArea { id: gameCcArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                controlCenter.opened = false;
                                if (root.gameArmed) root.gameExit();
                                else if (root.gameModeActive) root.gameCancel();
                                else root.gameEnter();
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: "#383847" }

                    Rectangle {
                        width: parent.width; height: 30; radius: 8
                        color: dashCcArea.containsMouse ? "#252532" : "#1d1d26"
                        Row { anchors.centerIn: parent; spacing: 8
                            Text { text: "\uf009"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 13 }
                            Text { text: "Dashboard"; color: "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 11 }
                        }
                        MouseArea { id: dashCcArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: { controlCenter.opened = false; widgetMenu.opened = true; }
                        }
                    }
                }
            }
        }

        PopupWindow {
            id: powerMenu
            implicitWidth: 280
            implicitHeight: powerCol.implicitHeight + 32
            visible: opened
            grabFocus: true
            color: "transparent"
            property bool opened: false
            property string pendingAction: ""
            property bool powerProfilesOpen: false
            onOpenedChanged: {
                if (!opened) {
                    powerProfilesOpen = false;
                    root.resetHover(ccArea);
                } else {
                    powerProfileStatus.running = true;
                }
            }

            anchor {
                window: root
                rect.x: root.width - powerMenu.implicitWidth - 12
                rect.y: root.height + 8
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 14
                color: "#e60d0d12"
                border.color: "#383847"
                border.width: 1
            }

            Column {
                id: powerCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    text: "ENERGÍA"
                    color: "#9a9aa7"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 3
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: powerMenu.pendingAction ? "¿Confirmar: " + powerMenu.pendingAction + "?" : "Selecciona una acción"
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 8
                    color: profileHeaderArea.containsMouse || powerMenu.powerProfilesOpen ? "#29233b" : "#262633"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        Text {
                            text: "\uf0e7"
                            color: "#cba6f7"
                            font.family: root.fontFamily
                            font.pixelSize: 13
                        }
                        Text {
                            text: "PERFIL DE ENERGÍA"
                            color: "#cdd6f4"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: (root.powerProfile || "desconocido").toUpperCase() + "  \uf078"
                            color: "#9a9aa7"
                            font.family: root.fontFamily
                            font.pixelSize: 8
                        }
                    }

                    MouseArea {
                        id: profileHeaderArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: powerMenu.powerProfilesOpen = !powerMenu.powerProfilesOpen
                    }
                }

                Column {
                    width: parent.width
                    spacing: 4
                    visible: powerMenu.powerProfilesOpen

                    Repeater {
                        model: ["power-saver", "balanced", "performance"]
                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width
                            height: 30
                            radius: 7
                            color: profileArea.containsMouse ? "#3a3850" : root.powerProfile === modelData ? "#29233b" : "#1d1d26"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                Text {
                                    text: root.powerProfile === modelData ? "●" : "○"
                                    color: root.powerProfile === modelData ? "#cba6f7" : "#6c7086"
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: modelData === "power-saver" ? "AHORRO" : modelData === "balanced" ? "EQUILIBRADO" : "RENDIMIENTO"
                                    color: "#cdd6f4"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData
                                    color: "#6c7086"
                                    font.family: root.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            MouseArea {
                                id: profileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    powerProfileSet.command = ["powerprofilesctl", "set", modelData];
                                    powerProfileSet.running = true;
                                    powerMenu.powerProfilesOpen = false;
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: ["SUSPENDER", "CERRAR SESIÓN", "REINICIAR", "APAGAR"]
                    delegate: Rectangle {
                        required property string modelData
                        width: powerCol.width
                        height: 34
                        radius: 8
                        color: powerActionArea.containsMouse ? (modelData === "APAGAR" ? "#e06c75" : "#cba6f7") : "#262633"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: powerActionArea.containsMouse ? "#11111b" : "#cdd6f4"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            id: powerActionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                powerMenu.pendingAction = modelData;
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 6
                    visible: powerMenu.pendingAction !== ""

                    Rectangle {
                        width: (parent.width - 6) / 2
                        height: 34
                        radius: 8
                        color: cancelPowerArea.containsMouse ? "#454554" : "#262633"
                        Text {
                            anchors.centerIn: parent
                            text: "CANCELAR"
                            color: "#cdd6f4"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                        }
                        MouseArea {
                            id: cancelPowerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: powerMenu.pendingAction = ""
                        }
                    }

                    Rectangle {
                        width: (parent.width - 6) / 2
                        height: 34
                        radius: 8
                        color: confirmPowerArea.containsMouse ? "#e06c75" : "#55232a"
                        Text {
                            anchors.centerIn: parent
                            text: "CONFIRMAR"
                            color: "white"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                        }
                        MouseArea {
                            id: confirmPowerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                powerAction.command = powerMenu.pendingAction === "SUSPENDER" ? ["systemctl", "suspend"] : powerMenu.pendingAction === "CERRAR SESIÓN" ? ["hyprctl", "dispatch", "exit"] : powerMenu.pendingAction === "REINICIAR" ? ["systemctl", "reboot"] : ["systemctl", "poweroff"];
                                powerMenu.opened = false;
                                powerMenu.pendingAction = "";
                                powerAction.running = true;
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#30303b"
                }

                Rectangle {
                    width: parent.width
                    height: 26
                    radius: 7
                    color: closePowerArea.containsMouse ? "#262633" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "CERRAR MENÚ"
                        color: "#8a8a99"
                        font.family: root.fontFamily
                        font.pixelSize: 9
                    }
                    MouseArea {
                        id: closePowerArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: powerMenu.opened = false
                    }
                }
            }
        }

        Process {
            id: powerAction
            command: ["true"]
            running: false
        }

        PopupWindow {
            id: dateMenu
            implicitWidth: 320
            implicitHeight: 150
            visible: opened
            grabFocus: true
            color: "transparent"
            property bool opened: false
            anchor { window: root; rect.x: (root.width - dateMenu.implicitWidth) / 2; rect.y: root.height + 8 }
            onOpenedChanged: if (!opened) root.resetHover(clockArea)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 14
                color: "#e60d0d12"
                border.color: "#383847"
                border.width: 1
                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8
                    Text { text: "CENTRO DE TAREAS"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2 }
                    Text { text: root.clockFull; color: "white"; font.family: root.fontFamily; font.pixelSize: 22; font.bold: true }
                    Text { text: "Calendario, tareas y actividad aparecerán aquí"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 10; wrapMode: Text.WordWrap }
                }
            }
        }

        PopupWindow {
            id: ramMenu
            implicitWidth: 300
            implicitHeight: 300
            visible: opened
            grabFocus: true
            color: "transparent"
            property bool opened: false
            property var processes: ListModel {}
            anchor { window: root; rect.x: root.width - ramMenu.implicitWidth - 190; rect.y: root.height + 8 }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 14
                color: "#e60d0d12"
                border.color: "#383847"
                border.width: 1
                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    RowLayout {
                        width: parent.width
                        Text { text: "RAM"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 13; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Text { text: ramText.text; color: "white"; font.family: root.fontFamily; font.pixelSize: 11 }
                    }
                    Text { text: "10 PROCESOS CON MAYOR CONSUMO"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; font.bold: true }
                    ListView {
                        width: parent.width
                        height: 220
                        clip: true
                        spacing: 4
                        model: ramMenu.processes
                        delegate: Rectangle {
                            required property string processName
                            required property string memory
                            width: parent ? parent.width : 0
                            height: 26
                            radius: 6
                            color: "#1d1d26"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text { text: processName; color: "white"; font.family: root.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: memory + " MB"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 9 }
                            }
                        }
                    }
                    Text { text: ramMenu.processes.count ? "Ordenados por RAM usada" : "Leyendo procesos..."; color: "#6c7086"; font.family: root.fontFamily; font.pixelSize: 9 }
                }
            }
            Process {
                id: ramMenuStatus
                command: ["bash", "-c", "ps -eo comm=,rss= --sort=-rss | awk 'NR <= 10 {printf \"%s|%.0f\\n\", $1, $2/1024}'"]
                running: false
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: line => { const p = line.trim().split("|"); if (p.length === 2) ramMenu.processes.append({ processName: p[0], memory: p[1] }); }
                }
            }
            onOpenedChanged: {
                if (opened) {
                    ramMenu.processes.clear();
                    ramMenuStatus.running = true;
                } else {
                    root.resetHover(ramArea);
                }
            }
        }

        PopupWindow {
            id: volumeMenu
            implicitWidth: 236
            implicitHeight: Math.max(132, volCol.implicitHeight + 26)
            visible: opened
            grabFocus: true
            color: "transparent"
            property bool opened: false
            property bool wallpaperMuted: false
            property bool wallpaperFound: false
            property string wallpaperSinkId: ""
            anchor { window: root; rect.x: root.width - volumeMenu.implicitWidth - 72; rect.y: root.height + 8 }
            onOpenedChanged: {
                if (opened) {
                    root.scanAudioDevices();
                    wallAudioStatus.running = true;
                } else {
                    root.resetHover(volumeArea);
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 12
                color: "#e60d0d12"
                border.color: "#383847"
                border.width: 1
                Column {
                    id: volCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    RowLayout {
                        width: parent.width
                        Text { text: "VOLUMEN"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.5 }
                        Item { Layout.fillWidth: true }
                        Text { text: root.volumeMuted ? "silenciado" : Math.round(root.volumePct) + "%"; color: "white"; font.family: root.fontFamily; font.pixelSize: 10 }
                    }
                    Row {
                        width: parent.width
                        spacing: 6
                        Rectangle {
                            width: parent.width - 54
                            height: 26
                            radius: 8
                            color: "#0d0d12"
                            border.color: "#30303b"
                            Rectangle { width: parent.width * Math.min(root.volumePct, 100) / 100; height: parent.height; radius: 8; color: "#89b4fa" }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: mouse => { volumeAdjust.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.max(0, Math.min(100, mouse.x / width * 100)).toFixed(0) + "%" ]; volumeAdjust.running = true; }
                            }
                        }
                        TextInput {
                            id: volumeInput
                            width: 48
                            height: 26
                            text: Math.round(root.volumePct).toString()
                            color: "white"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            selectByMouse: true
                            inputMethodHints: Qt.ImhDigitsOnly
                            onAccepted: { volumeAdjust.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.max(0, Math.min(100, parseFloat(text) || 0)).toFixed(0) + "%" ]; volumeAdjust.running = true; focus = false; }
                            Rectangle { anchors.fill: parent; z: -1; radius: 7; color: "#0d0d12"; border.color: "#30303b" }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: "#30303b" }

                    Row {
                        width: parent.width
                        spacing: 6
                        visible: volumeMenu.wallpaperFound

                        Text {
                            width: parent.width - 54
                            height: 26
                            verticalAlignment: Text.AlignVCenter
                            text: "\uf001  Audio del wallpaper"
                            color: "white"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: 48
                            height: 26
                            radius: 7
                            color: wallAudioToggleArea.containsMouse ? "#cba6f7" : volumeMenu.wallpaperMuted ? "#262633" : "#29233b"
                            border.color: "#30303b"

                            Text {
                                anchors.centerIn: parent
                                text: volumeMenu.wallpaperMuted ? "OFF" : "ON"
                                color: wallAudioToggleArea.containsMouse ? "#11111b" : volumeMenu.wallpaperMuted ? "#cdd6f4" : "#cba6f7"
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }

                            MouseArea {
                                id: wallAudioToggleArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (!volumeMenu.wallpaperSinkId)
                                        return;
                                    wallAudioToggle.command = ["wpctl", "set-mute", volumeMenu.wallpaperSinkId, volumeMenu.wallpaperMuted ? "0" : "1"];
                                    wallAudioToggle.running = false;
                                    wallAudioToggle.running = true;
                                }
                            }
                        }
                    }

                    Text {
                        text: "SALIDAS"
                        color: "#9a9aa7"
                        font.family: root.fontFamily
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1.5
                        visible: root.audioSinks.count > 0
                    }

                    Repeater {
                        model: root.audioSinks

                        delegate: Rectangle {
                            required property string deviceId
                            required property string name
                            required property bool selected
                            width: parent.width
                            height: 22
                            radius: 6
                            color: volSinkArea.containsMouse ? "#252532" : selected ? "#29233b" : "#14141b"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: (selected ? "●  " : "○  ") + name
                                color: selected ? "#cba6f7" : "white"
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: volSinkArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.setDefaultDevice(deviceId)
                            }
                        }
                    }

                    Text {
                        text: "ENTRADAS"
                        color: "#9a9aa7"
                        font.family: root.fontFamily
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1.5
                        visible: root.audioSources.count > 0
                    }

                    Repeater {
                        model: root.audioSources

                        delegate: Rectangle {
                            required property string deviceId
                            required property string name
                            required property bool selected
                            width: parent.width
                            height: 22
                            radius: 6
                            color: volSourceArea.containsMouse ? "#252532" : selected ? "#29233b" : "#14141b"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: (selected ? "●  " : "○  ") + name
                                color: selected ? "#cba6f7" : "white"
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: volSourceArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.setDefaultDevice(deviceId)
                            }
                        }
                    }
                }
            }
            Process { id: volumeAdjust; command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"]; running: false; onExited: volumeStatus.running = true }

            Process {
                id: wallAudioStatus
                command: ["bash", "-c", "id=$(wpctl status | sed -n '/^Audio$/,/^Video$/p' | grep -i wallpaper | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\.$/) {gsub(/\\./,\"\",$i); print $i; exit}}'); [ -n \"$id\" ] && { printf '%s|' \"$id\"; wpctl get-volume \"$id\"; }"]
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        const t = this.text.trim();
                        const bar = t.indexOf("|");
                        volumeMenu.wallpaperFound = bar > 0;
                        volumeMenu.wallpaperSinkId = bar > 0 ? t.slice(0, bar) : "";
                        volumeMenu.wallpaperMuted = /MUTED/.test(t);
                    }
                }
            }

            Process {
                id: wallAudioToggle
                command: ["true"]
                running: false
                onExited: wallAudioStatus.running = true
            }
        }

        PopupWindow {
            id: widgetMenu
             implicitWidth: 520
            implicitHeight: menuCol.implicitHeight
            visible: opened
            grabFocus: true
            color: "transparent"

              property bool opened: false
              property string activeSection: "conexiones"
              property double cpuUsage: 0
              property double cpuTemp: 0
              property double gpuUsage: 0
              property double gpuTemp: 0
              property double gpuMemory: 0
              property double gpuMemoryTotal: 0
              property double gpuPower: 0
              property double gpuPowerLimit: 0
              property double rootDisk: 0
              property string systemLoad: "--"
              property string systemUptime: "--"
              property bool gpuTelemetryAvailable: false
              property string monitorDetail: ""
              property var cpuThreads: ListModel {}

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
                    if (activeSection !== "dispositivos")
                        return;
                    root.scanAudioDevices();
                    audioCard.refreshCameras();
                }

                function refreshScreens() {
                    if (activeSection === "pantallas")
                        screenCard.refresh();
                }

                function refreshMonitoring() {
                    if (activeSection === "monitoreo" && !telemetryStatus.running)
                        telemetryStatus.running = true;
                }

                function openMonitorDetail(detail) {
                    monitorDetail = detail;
                    refreshMonitoring();
                    if (detail === "ram") {
                        ramCard.processes.clear();
                        ramProcessesStatus.running = true;
                    }
                    if (detail === "cpu") {
                        widgetMenu.cpuThreads.clear();
                        cpuThreadsStatus.running = true;
                    }
                }

              onOpenedChanged: {
                   if (opened) {
                       initialRefresh.restart();
                        refreshAudio();
                        refreshScreens();
                        refreshMonitoring();
                   } else {
                       root.resetHover(menuBtnArea);
                   }
              }

              Timer {
                  id: initialRefresh
                 interval: 700
                 repeat: false
                  onTriggered: widgetMenu.refreshConnections()
              }

              Process {
                  id: telemetryStatus
                   command: ["bash", "-c", "read -r _ u n s i w irq sirq st _ < /proc/stat; a=$((u+n+s+i+w+irq+sirq+st)); b=$i; sleep .15; read -r _ u n s i w irq sirq st _ < /proc/stat; c=$((u+n+s+i+w+irq+sirq+st)); d=$i; cpu=$(awk -v da=$((c-a)) -v di=$((d-b)) 'BEGIN { if (da > 0) print 100 * (da-di) / da; else print 0 }'); temp=$(for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); case $n in coretemp|k10temp|zenpower|cpu_thermal) for f in $h/temp*_input; do awk '{print int($1/1000)}' $f; done;; esac; done | sort -nr | head -n1); [ -n $temp ] || temp=0; load=$(awk '{print $1}' /proc/loadavg); up=$(cut -d. -f1 /proc/uptime); disk=$(df -P / | awk 'NR==2 {print $5}'); gpu=none; if command -v nvidia-smi >/dev/null 2>&1; then gpu=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,power.limit --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' '); fi; printf '%s|%s|%s|%s|%s|%s\\n' $cpu $temp $load $up $disk $gpu"]
                  running: false
                  stdout: StdioCollector {
                      onStreamFinished: {
                          const p = this.text.trim().split("|");
                          if (p.length < 6)
                              return;
                          widgetMenu.cpuUsage = Math.max(0, Math.min(100, parseFloat(p[0]) || 0));
                          widgetMenu.cpuTemp = parseFloat(p[1]) || 0;
                          widgetMenu.systemLoad = p[2] || "--";
                          widgetMenu.systemUptime = p[3] || "--";
                          widgetMenu.rootDisk = parseFloat(p[4]) || 0;
                          const g = p[5].split(",");
                          widgetMenu.gpuTelemetryAvailable = g.length >= 6;
                          widgetMenu.gpuUsage = parseFloat(g[0]) || 0;
                          widgetMenu.gpuTemp = parseFloat(g[1]) || 0;
                          widgetMenu.gpuMemory = parseFloat(g[2]) || 0;
                          widgetMenu.gpuMemoryTotal = parseFloat(g[3]) || 0;
                          widgetMenu.gpuPower = parseFloat(g[4]) || 0;
                          widgetMenu.gpuPowerLimit = parseFloat(g[5]) || 0;
                      }
                  }
              }

              Process {
                  id: cpuThreadsStatus
                  command: ["bash", "-c", "a=$(mktemp); b=$(mktemp); awk '/^cpu[0-9]+ / {print}' /proc/stat > $a; sleep .15; awk '/^cpu[0-9]+ / {print}' /proc/stat > $b; awk 'NR==FNR {u[$1]=$2; n[$1]=$3; s[$1]=$4; i[$1]=$5; w[$1]=$6; q[$1]=$7+$8+$9; next} {old=u[$1]+n[$1]+s[$1]+i[$1]+w[$1]+q[$1]; now=$2+$3+$4+$5+$6+$7+$8+$9; total=now-old; idle=$5-i[$1]; if (total > 0) print $1, 100*(total-idle)/total}' $a $b; rm -f $a $b"]
                  running: false
                  stdout: SplitParser {
                      splitMarker: "\n"
                      onRead: line => {
                          const p = line.trim().split(/\s+/);
                          if (p.length === 2)
                              widgetMenu.cpuThreads.append({ threadName: p[0], threadUsage: p[1] });
                      }
                  }
              }

              Timer {
                  interval: 2500
                  running: widgetMenu.opened && widgetMenu.activeSection === "monitoreo"
                  repeat: true
                  onTriggered: widgetMenu.refreshMonitoring()
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
                     visible: widgetMenu.monitorDetail === ""
                     opacity: widgetMenu.opened ? 1 : 0
                     scale: widgetMenu.opened ? 1 : 0.94
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
                        visible: widgetMenu.monitorDetail === ""

                         RowLayout {
                             width: parent.width
                             height: 24

                            Text {
                                 text: "SISTEMA  /  " + widgetMenu.activeSection.toUpperCase()
                                color: "#a6adc8"
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
                                      model: ["CONEXIONES", "MONITOREO", "PANTALLAS", "DISPOSITIVOS", "NOTIFICACIONES"]

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
                                                   widgetMenu.refreshScreens();
                                                   widgetMenu.refreshMonitoring();
                                              }
                                         }
                                     }
                                 }
                             }
                         }

                          Rectangle {
                              id: ramCard
                              width: parent.width
                              height: ramProcessesOpen ? 96 + ramCard.processes.count * 16 : 84
                              radius: 14
                              color: "#16161c"
                              border.color: "#26262e"
                              border.width: 1
                              visible: widgetMenu.activeSection === "monitoreo"
                              property double usedGiB: 0
                              property double totGiB: 0
                              property double usedPct: 0
                              property bool ramProcessesOpen: false
                              property var processes: ListModel {}

                              Column {
                                  anchors.left: parent.left
                                  anchors.right: parent.right
                                  anchors.top: parent.top
                                  anchors.margins: 14
                                  spacing: 8
RowLayout {
                                       width: parent.width
                                       Text { text: "\uf538"; color: "#cba6f7"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 23; Layout.preferredWidth: 28 }
                                       Text { text: "RAM"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 13; font.bold: true }
                                       Text { text: Math.round(ramCard.usedPct) + "%"; color: "white"; font.family: root.fontFamily; font.pixelSize: 20 }
                                       Item { Layout.fillWidth: true }
                                       Text { text: ramCard.usedGiB.toFixed(1) + "G / " + ramCard.totGiB.toFixed(1) + "G"; color: "#a6adc8"; font.family: root.fontFamily; font.pixelSize: 10 }
                                  }
                                  Rectangle { width: parent.width; height: 5; radius: 3; color: "#29233b"; Rectangle { width: parent.width * ramCard.usedPct / 100; height: parent.height; radius: 3; color: "#cba6f7" } }
                                  Column {
                                      id: ramProcesses
                                      width: parent.width
                                      spacing: 3
                                      visible: ramCard.ramProcessesOpen
                                      Repeater {
                                          model: ramCard.processes
                                          delegate: RowLayout {
                                              width: ramProcesses.width
                                              Text { text: processName; color: "white"; font.family: root.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                              Text { text: memory + " MB"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 9 }
                                          }
                                      }
                                  }
                              }
                               MouseArea { anchors.fill: parent; z: 1; onClicked: widgetMenu.openMonitorDetail("ram") }

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
                                              if (totMiB > 0) { ramCard.usedPct = usedMiB / totMiB * 100; ramCard.usedGiB = usedMiB / 1024; ramCard.totGiB = totMiB / 1024; }
                                          }
                                      }
                                  }
                              }
                              Process {
                                  id: ramProcessesStatus
                                  command: ["bash", "-c", "ps -eo comm=,rss= --sort=-rss | awk 'NR <= 8 {printf \"%s|%.0f\\n\", $1, $2/1024}'"]
                                  running: false
                                  stdout: SplitParser {
                                      splitMarker: "\n"
                                      onRead: line => { const p = line.trim().split("|"); if (p.length === 2) ramCard.processes.append({ processName: p[0], memory: p[1] }); }
                                  }
                              }
                              Timer { interval: 3000; running: true; repeat: true; onTriggered: ramFree.running = true }
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
                            property bool hasTelemetry: widgetMenu.gpuTelemetryAvailable
                            property string modo: ""
                            property string fuente: ""
                            property string acpi: ""

                            cIcon: gpuCard.modo === "gaming" ? "\uf11b" : gpuCard.acpi === "off" ? "\uf011" : gpuCard.modo === "disabled" ? "\uf2db" : "\uf06c"
                            cAccent: gpuCard.modo === "gaming" ? "#98c379" : gpuCard.acpi === "off" ? "#98c379" : gpuCard.modo === "disabled" ? "#e5c07b" : widgetMenu.gpuTemp >= 85 ? "#e06c75" : "#98c379"
                            cTitle: "GPU NVIDIA"
                            cBig: root.hasBattery
                                ? (gpuCard.modo === "gaming" ? "Juegos"
                                    : gpuCard.acpi === "off" ? "OFF"
                                    : gpuCard.modo === "disabled" ? "D3cold"
                                    : (gpuCard.hasTelemetry ? Math.round(widgetMenu.gpuUsage) + "%" : "Auto"))
                                : (gpuCard.hasTelemetry ? Math.round(widgetMenu.gpuUsage) + "%" : "NO DETECTADA")
                            cVal: gpuCard.hasTelemetry ? widgetMenu.gpuUsage : (root.hasBattery ? 0 : 0)
                            cSub: root.hasBattery
                                ? (gpuCard.hasTelemetry
                                    ? Math.round(widgetMenu.gpuTemp) + "\u00b0C \u00b7 " + Math.round(widgetMenu.gpuMemory) + "/" + Math.round(widgetMenu.gpuMemoryTotal) + " MB \u00b7 " + Math.round(widgetMenu.gpuPower) + "/" + Math.round(widgetMenu.gpuPowerLimit) + " W"
                                    : (gpuCard.fuente ? "ACPI: " + gpuCard.acpi : "NVIDIA inactiva"))
                                : (gpuCard.hasTelemetry ? Math.round(widgetMenu.gpuTemp) + "\u00b0C \u00b7 " + Math.round(widgetMenu.gpuMemory) + "/" + Math.round(widgetMenu.gpuMemoryTotal) + " MB \u00b7 " + Math.round(widgetMenu.gpuPower) + "/" + Math.round(widgetMenu.gpuPowerLimit) + " W" : "nvidia-smi no disponible")
                            dDel: root.hasBattery ? 120 : 30
                            cardOn: widgetMenu.opened
                            visible: widgetMenu.activeSection === "monitoreo"

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.hasBattery) {
                                        const p = gpuToggle;
                                        p.running = false;
                                        p.running = true;
                                    } else {
                                        widgetMenu.openMonitorDetail("gpu");
                                    }
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
                                        if (m) gpuCard.modo = m[1];
                                        m = line.match(/Fuente:\s*(\w+)/);
                                        if (m) gpuCard.fuente = m[1];
                                        m = line.match(/ACPI:\s*(\w+)/);
                                        if (m) gpuCard.acpi = m[1];
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
                              height: audioDetailsOpen ? audioDetails.y + audioDetails.implicitHeight + 12 : 70
                              radius: 12
                              color: "#16161c"
                              border.color: "#26262e"
                              border.width: 1
                              visible: widgetMenu.activeSection === "dispositivos"

                              property bool audioDetailsOpen: true
                              property string audioMessage: ""
                              property var cameras: ListModel {}

                              function refreshCameras() {
                                  cameras.clear();
                                  cameraStatus.running = false;
                                  cameraStatus.running = true;
                              }

                              function parseCamera(line) {
                                  const parts = line.split("|");
                                  if (parts.length < 2)
                                      return;
                                  cameras.append({ device: parts[0], name: parts[1] || parts[0] });
                              }

                              function selectDevice(id, label) {
                                  audioCard.audioMessage = "Seleccionando " + label + "...";
                                  root.setDefaultDevice(id);
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
                                          text: root.audioSinks.count + " salidas · " + root.audioSources.count + " entradas · " + audioCard.cameras.count + " cámaras"
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
                                   anchors.topMargin: 70
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
                                      visible: audioCard.cameras.count > 0
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
                                      visible: root.audioSinks.count > 0
                                  }

                                  Repeater {
                                      model: root.audioSinks
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
                                      visible: root.audioSources.count > 0
                                  }

                                  Repeater {
                                      model: root.audioSources
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
                                  id: cameraStatus
                                  command: ["bash", "-c", "for d in /dev/video*; do [ -e \"$d\" ] || continue; name=$(udevadm info -q property -n \"$d\" 2>/dev/null | awk -F= '/^ID_V4L_PRODUCT=/{print $2; exit}'); printf '%s|%s\\n' \"$d\" \"${name:-$d}\"; done"]
                                  running: false
                                  stdout: SplitParser {
                                      splitMarker: "\n"
                                      onRead: line => audioCard.parseCamera(line)
                                  }
                              }
                          }

                           Card {
                               id: cpuCard
                               cIcon: "\uf2db"
                               cAccent: widgetMenu.cpuTemp >= 90 ? "#e06c75" : widgetMenu.cpuTemp >= 75 ? "#e5c07b" : "#89b4fa"
                               cTitle: "CPU"
                               cBig: Math.round(widgetMenu.cpuUsage) + "%"
                               cVal: widgetMenu.cpuUsage
                               cSub: widgetMenu.cpuTemp > 0 ? Math.round(widgetMenu.cpuTemp) + "°C" : "Temperatura ---"
                               dDel: 180
                               cardOn: widgetMenu.opened
                               visible: widgetMenu.activeSection === "monitoreo"
                               MouseArea { anchors.fill: parent; onClicked: widgetMenu.openMonitorDetail("cpu") }
                           }

                            Card {
                               id: systemCard
                               cIcon: "\uf080"
                               cAccent: widgetMenu.rootDisk >= 90 ? "#e06c75" : "#cba6f7"
                               cTitle: "SISTEMA"
                               cBig: widgetMenu.rootDisk + "%"
                               cVal: widgetMenu.rootDisk
                               cSub: "Carga " + widgetMenu.systemLoad + " · Up " + widgetMenu.systemUptime
                               dDel: 240
                               cardOn: widgetMenu.opened
                               visible: widgetMenu.activeSection === "monitoreo"
                               MouseArea { anchors.fill: parent; onClicked: widgetMenu.openMonitorDetail("sistema") }
                           }

                           Rectangle {
                               id: screenCard
                               width: parent.width
                               height: 360
                               radius: 12
                               color: "#16161c"
                               border.color: "#26262e"
                               border.width: 1
                               visible: widgetMenu.activeSection === "pantallas"
                               property var monitors: ListModel {}
                               property string screenMessage: ""

                               function refresh() {
                                   monitors.clear();
                                   screenMessage = "Leyendo pantallas...";
                                   screenStatus.running = false;
                                   screenStatus.running = true;
                               }

                               function apply(name, action) {
                                   let monitor = null;
                                   for (let i = 0; i < monitors.count; i++)
                                       if (monitors.get(i).name === name) monitor = monitors.get(i);
                                   if (!monitor) return;
                                   let command;
                                   if (action === "duplicate")
                                       command = "hyprctl keyword monitor '" + name + ",preferred,auto,1,mirror," + monitor.primary + "'";
                                   else if (action === "extend")
                                       command = "hyprctl keyword monitor '" + name + ",preferred," + monitor.mx + "x" + monitor.my + "," + monitor.mscale + "'";
                                   else if (action === "second")
                                       command = "hyprctl keyword monitor '" + monitor.primary + ",disable'; hyprctl keyword monitor '" + name + ",preferred,auto,1'";
                                   else if (action === "only")
                                       command = "hyprctl keyword monitor '" + name + ",preferred,auto,1'; hyprctl keyword monitor '" + monitor.primary + ",disable'";
                                   else {
                                       const dx = action === "left" ? -100 : action === "right" ? 100 : 0;
                                       const dy = action === "up" ? -100 : action === "down" ? 100 : 0;
                                       command = "hyprctl keyword monitor '" + name + ",preferred," + (monitor.mx + dx) + "x" + (monitor.my + dy) + "," + monitor.mscale + "'";
                                   }
                                   screenAction.command = ["bash", "-c", command];
                                   screenAction.running = true;
                               }

                               Column {
                                   anchors.fill: parent
                                   anchors.margins: 14
                                   spacing: 9
                                   Text { text: "PANTALLAS"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.5 }
                                   Text { text: "Configura cómo usar cada monitor conectado"; color: "white"; font.family: root.fontFamily; font.pixelSize: 13 }
                                   ListView {
                                       width: parent.width
                                       height: 190
                                       clip: true
                                       spacing: 6
                                       model: screenCard.monitors
                                       delegate: Rectangle {
                                           required property string name
                                           required property string description
                                           required property string primary
                                           required property int mx
                                           required property int my
                                           width: parent ? parent.width : 0
                                           height: 48
                                           radius: 8
                                           color: "#1d1d26"
                                           Column {
                                               anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                               Text { text: name; color: "white"; font.family: root.fontFamily; font.pixelSize: 11 }
                                               Text { text: description; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; width: 390 }
                                           }
                                       }
                                   }
                                   RowLayout {
                                       width: parent.width; spacing: 5
                                       Repeater {
                                           model: ["DUPLICAR", "AMPLIAR", "SOLO 2ª", "SOLO ESTA"]
                                           delegate: Rectangle {
                                               required property string modelData
                                               Layout.fillWidth: true; height: 32; radius: 7
                                               color: screenModeArea.containsMouse ? "#cba6f7" : "#262633"
                                               Text { anchors.centerIn: parent; text: modelData; color: screenModeArea.containsMouse ? "#11111b" : "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 8; font.bold: true }
                                               MouseArea { id: screenModeArea; anchors.fill: parent; hoverEnabled: true; onClicked: { if (screenCard.monitors.count) screenCard.apply(screenCard.monitors.get(screenCard.monitors.count - 1).name, modelData === "DUPLICAR" ? "duplicate" : modelData === "AMPLIAR" ? "extend" : modelData === "SOLO 2ª" ? "second" : "only"); } }
                                           }
                                       }
                                   }
                                   RowLayout {
                                       width: parent.width; spacing: 5
                                       Text { text: "POSICIÓN"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; font.bold: true }
                                       Item { Layout.fillWidth: true }
                                       Repeater {
                                           model: [["←", "left"], ["→", "right"], ["↑", "up"], ["↓", "down"]]
                                           delegate: Rectangle {
                                               required property var modelData
                                               width: 30; height: 28; radius: 7; color: positionArea.containsMouse ? "#cba6f7" : "#262633"
                                               Text { anchors.centerIn: parent; text: modelData[0]; color: "#cdd6f4"; font.pixelSize: 14 }
                                               MouseArea { id: positionArea; anchors.fill: parent; hoverEnabled: true; onClicked: { if (screenCard.monitors.count) screenCard.apply(screenCard.monitors.get(screenCard.monitors.count - 1).name, modelData[1]); } }
                                           }
                                       }
                                   }
                                   Text { text: screenCard.screenMessage || "Selecciona modo o mueve pantalla en pasos de 100 px"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
                               }

                               Process {
                                   id: screenStatus
                                   command: ["bash", "-c", "hyprctl monitors -j | jq -r '.[] | [.name, (.description // .name), (.x|tostring), (.y|tostring), (.scale|tostring), (.focused|tostring)] | @tsv'"]
                                   running: false
                                   stdout: SplitParser {
                                       splitMarker: "\n"
                                       onRead: line => {
                                           const p = line.split("\t");
                                           if (p.length < 6) return;
                                           const primary = p[5] === "true" ? p[0] : (screenCard.monitors.count ? screenCard.monitors.get(0).primary : p[0]);
                                           screenCard.monitors.append({ name: p[0], description: p[1], mx: parseInt(p[2]), my: parseInt(p[3]), mscale: parseFloat(p[4]), primary: primary });
                                       }
                                   }
                                   onExited: screenCard.screenMessage = screenCard.monitors.count ? "Elige modo de pantalla" : "No se detectaron pantallas"
                               }
                               Process { id: screenAction; command: ["true"]; running: false; onExited: { screenCard.screenMessage = exitCode === 0 ? "Configuración aplicada" : "No se pudo cambiar pantalla"; screenCard.refresh(); } }
                           }

                           Rectangle {
                              id: wifiCard
                             width: parent.width
                             height: wifiDetailsOpen ? 70 + wifiDetails.implicitHeight + 12 : 70
                              radius: 12
                              color: "#16161c"
                              border.color: wifiCard.wifiState === "failed" ? "#e06c75" : "#26262e"
                              border.width: 1
                              visible: widgetMenu.activeSection === "conexiones"

                             property bool wifiOn: false
                             property string network: "Sin conexión"
                             property bool wifiDetailsOpen: false
                             property string wifiMessage: ""
                             property string selectedSsid: ""
                             property string wifiState: "disconnected" // off | disconnected | connecting | connected | failed
                             property string lastError: ""
                             property int wifiSignal: 0
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
                              property var wifiScanNetworks: ListModel {}

                              function refreshNetworks() {
                                  wifiCard.wifiMessage = "Buscando redes...";
                                  wifiScanNetworks.clear();
                                  wifiScan.running = false;
                                  wifiScan.running = true;
                              }

                              function toggleNetwork(index) {
                                  for (let i = 0; i < wifiNetworks.count; i++)
                                      wifiNetworks.setProperty(i, "expanded", i === index ? !wifiNetworks.get(i).expanded : false);
                                  wifiCard.selectedSsid = wifiNetworks.get(index).ssid;
                                  wifiCard.wifiAdvancedOpen = false;
                                  wifiCard.wifiMessage = wifiCard.selectedSsid + " seleccionada";
                              }

                              function connectNetwork(ssid) {
                                  wifiCard.selectedSsid = ssid;
                                  if (wifiCard.wifiState === "connecting")
                                      return;
                                  wifiConnect.command = wifiCard.connectCommand();
                                  wifiCard.wifiState = "connecting";
                                  wifiCard.lastError = "";
                                  wifiCard.wifiMessage = "Conectando a " + ssid + "…";
                                  wifiConnect.running = false;
                                  wifiConnect.running = true;
                              }

                             function connErrorMessage(raw, code) {
                                 const t = (raw || "").trim();
                                 if (!t)
                                     return "No se pudo conectar (error " + code + ")";
                                 if (/secret|password|contrase/i.test(t))
                                     return "Contraseña incorrecta o rechazada";
                                 if (/timed?[\s-]*out|timeout/i.test(t))
                                     return "Tiempo agotado — reintenta cerca del router";
                                 if (/no network with ssid/i.test(t))
                                     return "Red no encontrada — escanea de nuevo";
                                 if (/no suitable device|not enabled|not available/i.test(t))
                                     return "Wi-Fi desactivado o sin adaptador";
                                 const lines = t.split("\n").filter(l => l.trim());
                                 const reason = lines.length ? lines[lines.length - 1].trim().replace(/^.*?:\s*/, "") : "";
                                 if (!reason)
                                     return "No se pudo conectar (error " + code + ")";
                                 return "No se pudo conectar: " + (reason.length > 70 ? reason.slice(0, 67) + "…" : reason);
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
                                 wifiScanNetworks.append({
                                     ssid: ssid,
                                     signal: signal,
                                     security: security || "Abierta",
                                     expanded: false
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
                                    color: wifiCard.wifiState === "connected" ? "#a6e3a1" : wifiCard.wifiState === "connecting" ? "#cba6f7" : wifiCard.wifiState === "failed" ? "#e06c75" : wifiCard.wifiOn ? "#89b4fa" : "#6c7086"
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
                                        text: {
                                            if (!wifiCard.wifiOn)
                                                return "Desactivado";
                                            if (wifiCard.wifiState === "connecting")
                                                return "Conectando a " + (wifiCard.selectedSsid || "red") + "…";
                                            if (wifiCard.wifiState === "failed")
                                                return wifiCard.lastError || "No se pudo conectar";
                                            const sig = wifiCard.wifiSignal > 0 && wifiCard.wifiState === "connected" && !wifiCard.network.startsWith("Cable:") ? "  ·  " + wifiCard.wifiSignal + "%" : "";
                                            return wifiCard.network + sig;
                                        }
                                        color: wifiCard.wifiState === "failed" ? "#e06c75" : wifiCard.wifiState === "connecting" ? "#89b4fa" : wifiCard.wifiState === "connected" ? "#a6e3a1" : "white"
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

                                Text {
                                    visible: wifiCard.wifiState === "connecting"
                                    text: "\uf110"
                                    color: "#89b4fa"
                                    font.family: root.fontFamily
                                    font.pixelSize: 13

                                    RotationAnimation on rotation {
                                        running: wifiCard.wifiState === "connecting"
                                        loops: Animation.Infinite
                                        duration: 1000
                                        from: 0
                                        to: 360
                                    }
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

                                       RowLayout {
                                           visible: false
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
                                       visible: false
                                       width: parent.width
                                     height: 32
                                     radius: 8
                                     color: wifiCard.wifiAdvancedOpen ? "#89b4fa" : wifiAdvancedArea.containsMouse ? "#262633" : "#1d1d26"
                                     Text {
                                         anchors.centerIn: parent
                                          text: wifiCard.wifiAdvancedOpen ? "OCULTAR CONFIGURACIÓN EMPRESARIAL" : "CONFIGURACIÓN EMPRESARIAL (802.1X)"
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
                                       visible: false

                                      Text {
                                          text: "RED UNIVERSITARIA O DE EMPRESA"
                                          color: "#9a9aa7"
                                          font.family: root.fontFamily
                                          font.pixelSize: 9
                                          font.bold: true
                                      }

                                      Text {
                                          width: parent.width
                                          text: "Usa esta opción solo si la red pide usuario además de contraseña."
                                          color: "#6c7086"
                                          font.family: root.fontFamily
                                          font.pixelSize: 9
                                          wrapMode: Text.WordWrap
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

                                  RowLayout {
                                      width: parent.width
                                      spacing: 6
                                      Text {
                                          text: wifiCard.wifiNetworks.count ? "REDES DISPONIBLES" : wifiCard.wifiMessage
                                          color: "#9a9aa7"
                                          font.family: root.fontFamily
                                          font.pixelSize: 9
                                          font.bold: true
                                          Layout.fillWidth: true
                                          elide: Text.ElideRight
                                      }
                                      Rectangle {
                                          width: 86
                                          height: 28
                                          radius: 7
                                          color: wifiScanArea.containsMouse ? "#89b4fa" : "#262633"
                                          Text { anchors.centerIn: parent; text: "ESCANEAR"; color: wifiScanArea.containsMouse ? "#11111b" : "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 8; font.bold: true }
                                          MouseArea { id: wifiScanArea; anchors.fill: parent; hoverEnabled: true; onClicked: wifiCard.refreshNetworks() }
                                      }
                                  }

                                  ListView {
                                     width: parent.width
                                      height: Math.min(contentHeight, 360)
                                     visible: count > 0
                                    clip: true
                                    model: wifiCard.wifiNetworks
                                    spacing: 3
                                     delegate: Rectangle {
                                         required property string ssid
                                         required property string signal
                                         required property string security
                                         required property bool expanded
                                         width: wifiDetails.width
                                          height: expanded ? 34 + networkDetails.implicitHeight + 10 : 34
                                          radius: 7
                                         color: wifiNetworkArea.containsMouse ? "#252532" : "#1d1d26"
                                         RowLayout {
                                             anchors.left: parent.left
                                             anchors.right: parent.right
                                             anchors.top: parent.top
                                             height: 34
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
                                             anchors.left: parent.left
                                             anchors.right: parent.right
                                             anchors.top: parent.top
                                             height: 34
                                             hoverEnabled: true
                                             onClicked: {
                                                 wifiCard.toggleNetwork(index);
                                                 if (wifiCard.wifiState === "failed") {
                                                     wifiCard.wifiState = "disconnected";
                                                     wifiCard.lastError = "";
                                                 }
                                             }
                                         }

                                         Column {
                                             id: networkDetails
                                             anchors.left: parent.left
                                             anchors.right: parent.right
                                             anchors.top: parent.top
                                             anchors.topMargin: 40
                                             spacing: 6
                                             visible: expanded

                                             RowLayout {
                                                 width: parent.width
                                                 spacing: 6
                                                 TextInput {
                                                     id: networkPasswordInput
                                                     Layout.fillWidth: true
                                                     height: 32
                                                     color: "white"
                                                     text: wifiCard.wifiPassword
                                                     font.family: root.fontFamily
                                                     font.pixelSize: 10
                                                     echoMode: TextInput.Password
                                                     padding: 7
                                                     onTextChanged: wifiCard.wifiPassword = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Contraseña"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                                 Rectangle {
                                                     width: 84
                                                     height: 32
                                                     radius: 8
                                                     color: wifiCard.wifiAdvancedOpen ? "#89b4fa" : networkAdvancedArea.containsMouse ? "#262633" : "#1d1d26"
                                                     Text { anchors.centerIn: parent; text: "AVANZADO"; color: wifiCard.wifiAdvancedOpen ? "#11111b" : "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 8; font.bold: true }
                                                     MouseArea { id: networkAdvancedArea; anchors.fill: parent; hoverEnabled: true; onClicked: wifiCard.wifiAdvancedOpen = !wifiCard.wifiAdvancedOpen }
                                                 }
                                             }

                                             Column {
                                                 width: parent.width
                                                 spacing: 6
                                                 visible: wifiCard.wifiAdvancedOpen
                                                 Text { text: "RED EMPRESARIAL / 802.1X"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 8; font.bold: true }
                                                 RowLayout {
                                                     width: parent.width
                                                     spacing: 6
                                                     TextInput {
                                                         Layout.fillWidth: true; height: 32; color: "white"; text: wifiCard.wifiIdentity; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                         onTextChanged: wifiCard.wifiIdentity = text
                                                         Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                         Text { anchors.fill: parent; anchors.margins: 7; text: "Usuario / identidad"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                     }
                                                     TextInput {
                                                         Layout.fillWidth: true; height: 32; color: "white"; text: wifiCard.wifiEap; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                         onTextChanged: wifiCard.wifiEap = text
                                                         Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                         Text { anchors.fill: parent; anchors.margins: 7; text: "EAP: peap / tls"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                     }
                                                 }
                                                 TextInput {
                                                     width: parent.width; height: 32; color: "white"; text: wifiCard.wifiPhase2; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                     onTextChanged: wifiCard.wifiPhase2 = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Fase 2: mschapv2"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                                 TextInput {
                                                     width: parent.width; height: 32; color: "white"; text: wifiCard.wifiAnonymousIdentity; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                     onTextChanged: wifiCard.wifiAnonymousIdentity = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Identidad anónima (opcional)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                                 TextInput {
                                                     width: parent.width; height: 32; color: "white"; text: wifiCard.wifiCaCert; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                     onTextChanged: wifiCard.wifiCaCert = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado CA (opcional)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                                 TextInput {
                                                     width: parent.width; height: 32; color: "white"; text: wifiCard.wifiDomain; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                     onTextChanged: wifiCard.wifiDomain = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Dominio (opcional)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                                 TextInput {
                                                     width: parent.width; height: 32; color: "white"; text: wifiCard.wifiClientCert; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                     onTextChanged: wifiCard.wifiClientCert = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Certificado cliente (EAP-TLS)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                                 TextInput {
                                                     width: parent.width; height: 32; color: "white"; text: wifiCard.wifiClientKey; font.family: root.fontFamily; font.pixelSize: 10; padding: 7
                                                     onTextChanged: wifiCard.wifiClientKey = text
                                                     Rectangle { anchors.fill: parent; z: -1; radius: 8; color: "#0d0d12"; border.color: "#30303b" }
                                                     Text { anchors.fill: parent; anchors.margins: 7; text: "Clave privada (EAP-TLS)"; color: "#6c7086"; font: parent.font; visible: !parent.text }
                                                 }
                                             }

                                             Rectangle {
                                                 width: parent.width
                                                 height: 34
                                                 radius: 8
                                                 color: wifiCard.wifiState === "connecting" ? "#1d1d26" : networkConnectArea.containsMouse ? "#89b4fa" : "#262633"
                                                 Text { anchors.centerIn: parent; text: wifiCard.wifiState === "connecting" ? "CONECTANDO…" : "CONECTAR"; color: wifiCard.wifiState === "connecting" ? "#6c7086" : networkConnectArea.containsMouse ? "#11111b" : "#cdd6f4"; font.family: root.fontFamily; font.pixelSize: 9; font.bold: true }
                                                 MouseArea { id: networkConnectArea; anchors.fill: parent; hoverEnabled: true; onClicked: wifiCard.connectNetwork(ssid) }
                                             }
                                         }
                                     }
                                 }

                                Text {
                                    width: parent.width
                                    text: wifiCard.wifiNetworks.count ? wifiCard.wifiMessage : (wifiCard.wifiMessage || "Buscando redes...")
                                    color: wifiCard.wifiState === "failed" ? "#e06c75" : wifiCard.wifiState === "connecting" ? "#89b4fa" : "#9a9aa7"
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                  Rectangle {
                                      visible: false
                                      width: parent.width
                                    height: 34
                                    radius: 8
                                    color: wifiCard.wifiState === "connecting" ? "#1d1d26" : wifiConnectArea.containsMouse ? "#89b4fa" : "#262633"
                                    Text {
                                        anchors.centerIn: parent
                                        text: wifiCard.wifiState === "connecting" ? "CONECTANDO…" : "CONECTAR" + (wifiCard.selectedSsid ? " · " + wifiCard.selectedSsid : "")
                                        color: wifiCard.wifiState === "connecting" ? "#6c7086" : wifiConnectArea.containsMouse ? "#11111b" : "#cdd6f4"
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
                                            if (!wifiCard.selectedSsid || wifiCard.wifiState === "connecting")
                                                return;
                                             wifiConnect.command = wifiCard.connectCommand();
                                            wifiCard.wifiState = "connecting";
                                            wifiCard.lastError = "";
                                            wifiCard.wifiMessage = "Conectando a " + wifiCard.selectedSsid + "…";
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
                                 onExited: {
                                     if (wifiCard.wifiScanNetworks.count) {
                                         wifiCard.wifiNetworks.clear();
                                         for (let i = 0; i < wifiCard.wifiScanNetworks.count; i++) {
                                             const network = wifiCard.wifiScanNetworks.get(i);
                                             wifiCard.wifiNetworks.append({ ssid: network.ssid, signal: network.signal, security: network.security, expanded: false });
                                         }
                                         wifiCard.wifiMessage = "Selecciona una red";
                                     } else if (!wifiCard.wifiNetworks.count) {
                                         wifiCard.wifiMessage = "nmcli no disponible o sin redes";
                                     } else {
                                         wifiCard.wifiMessage = "No se encontraron redes nuevas";
                                     }
                                     wifiCard.wifiScanNetworks.clear();
                                 }
                            }

                            Process {
                                id: wifiConnect
                                command: ["nmcli", "dev", "wifi", "connect", ""]
                                running: false
                                stderr: StdioCollector {
                                    id: wifiConnectErr
                                }
                                onExited: {
                                    if (exitCode === 0) {
                                        wifiCard.wifiState = "connected";
                                        wifiCard.lastError = "";
                                        wifiCard.wifiMessage = "Conectado a " + wifiCard.selectedSsid;
                                        wifiCard.wifiPassword = "";
                                        wifiPasswordInput.text = "";
                                    } else {
                                        wifiCard.wifiState = "failed";
                                        wifiCard.lastError = wifiCard.connErrorMessage(wifiConnectErr.text, exitCode);
                                        wifiCard.wifiMessage = wifiCard.lastError;
                                    }
                                    wifiStatus.running = false;
                                    wifiStatus.running = true;
                                }
                            }

                            Process {
                                id: wifiStatus
                                 command: ["bash", "-c", "export LC_ALL=C; enabled=$(nmcli -t -f WIFI g | head -n1); network=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1==\"yes\"{sub(/^yes:/,\"\"); print; exit}'); signal=$(nmcli -t -f active,signal dev wifi | awk -F: '$1==\"yes\"{print $2; exit}'); wired=$(nmcli -t -f TYPE,STATE,CONNECTION dev | awk -F: '$1==\"ethernet\" && $2==\"connected\"{print $3; exit}'); printf '%s|%s|%s|%s' \"$enabled\" \"$network\" \"$wired\" \"$signal\""]
                                running: true

                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        if (wifiCard.wifiState === "connecting")
                                            return;
                                        const parts = this.text.trim().split("|");
                                        wifiCard.wifiOn = parts[0] === "enabled";
                                        wifiCard.wifiSignal = parseInt(parts[3]) || 0;
                                        const net = parts[1] || "";
                                        const wired = parts[2] || "";
                                        if (!wifiCard.wifiOn) {
                                            wifiCard.network = "Desactivado";
                                            wifiCard.wifiState = "off";
                                        } else if (net) {
                                            wifiCard.network = net;
                                            wifiCard.wifiState = "connected";
                                        } else if (wired) {
                                            wifiCard.network = "Cable: " + wired;
                                            wifiCard.wifiState = "connected";
                                        } else {
                                            wifiCard.network = "Sin conexión";
                                            if (wifiCard.wifiState !== "failed")
                                                wifiCard.wifiState = "disconnected";
                                        }
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

                        Rectangle {
                            id: notifCard
                            width: parent.width
                            height: 208
                            radius: 12
                            color: "#16161c"
                            border.color: "#26262e"
                            border.width: 1
                            visible: widgetMenu.activeSection === "notificaciones"
                            property bool soundOn: true
                            property bool voiceOn: false

                            function refresh() {
                                soundStateRead.running = false;
                                soundStateRead.running = true;
                                voiceStateRead.running = false;
                                voiceStateRead.running = true;
                            }

                            function writeFile(name, val) {
                                soundStateWrite.command = ["bash", "-c", "mkdir -p \"$HOME/.local/state/opencode\" && printf '" + val + "' > \"$HOME/.local/state/opencode/" + name + "\""];
                                soundStateWrite.running = false;
                                soundStateWrite.running = true;
                            }

                            function fmtBool(b) { return b ? "1" : "0"; }

                            onVisibleChanged: if (visible) refresh()

                            Process {
                                id: soundStateRead
                                command: ["bash", "-c", "cat \"$HOME/.local/state/opencode/notify-sound-enabled\" 2>/dev/null || echo 1"]
                                running: false
                                stdout: StdioCollector {
                                    onStreamFinished: notifCard.soundOn = this.text.trim() !== "0"
                                }
                            }
                            Process {
                                id: voiceStateRead
                                command: ["bash", "-c", "cat \"$HOME/.local/state/opencode/notify-voice-enabled\" 2>/dev/null || echo 0"]
                                running: false
                                stdout: StdioCollector {
                                    onStreamFinished: notifCard.voiceOn = this.text.trim() === "1"
                                }
                            }
                            Process { id: soundStateWrite; command: ["true"]; running: false }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 12
                                spacing: 10

                                RowLayout {
                                    width: parent.width

                                    Text {
                                        text: "\uf0f3"
                                        color: notifCard.soundOn ? "#cba6f7" : "#6c7086"
                                        font.family: root.fontFamily
                                        font.pixelSize: 22
                                        Layout.preferredWidth: 28
                                    }

                                    Column {
                                        spacing: 2
                                        Layout.fillWidth: true

                                        Text {
                                            text: "NOTIFICACIONES"
                                            color: "#9a9aa7"
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                        }

                                        Text {
                                            text: notifCard.soundOn ? "Sonido activado" : "Sonido silenciado"
                                            color: notifCard.soundOn ? "white" : "#6c7086"
                                            font.family: root.fontFamily
                                            font.pixelSize: 14
                                        }
                                    }

                                    Rectangle {
                                        width: 48
                                        height: 30
                                        radius: 9
                                        color: soundToggleArea.containsMouse ? "#cba6f7" : "#262633"

                                        Text {
                                            anchors.centerIn: parent
                                            text: notifCard.soundOn ? "ON" : "OFF"
                                            color: soundToggleArea.containsMouse ? "#11111b" : "#cdd6f4"
                                            font.family: root.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: soundToggleArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                const next = !notifCard.soundOn;
                                                notifCard.soundOn = next;
                                                notifCard.writeFile("notify-sound-enabled", notifCard.fmtBool(next));
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width

                                    Text {
                                        text: "\uf130"
                                        color: notifCard.voiceOn ? "#89dceb" : "#6c7086"
                                        font.family: root.fontFamily
                                        font.pixelSize: 20
                                        Layout.preferredWidth: 28
                                    }

                                    Column {
                                        spacing: 2
                                        Layout.fillWidth: true

                                        Text {
                                            text: "VOZ DEL RESUMEN"
                                            color: "#9a9aa7"
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.letterSpacing: 1.5
                                        }

                                        Text {
                                            text: notifCard.voiceOn ? "Habla el resumen al terminar" : "Solo notificación escrita"
                                            color: notifCard.voiceOn ? "white" : "#6c7086"
                                            font.family: root.fontFamily
                                            font.pixelSize: 13
                                        }
                                    }

                                    Rectangle {
                                        width: 48
                                        height: 30
                                        radius: 9
                                        color: voiceToggleArea.containsMouse ? "#89dceb" : "#262633"

                                        Text {
                                            anchors.centerIn: parent
                                            text: notifCard.voiceOn ? "ON" : "OFF"
                                            color: voiceToggleArea.containsMouse ? "#11111b" : "#cdd6f4"
                                            font.family: root.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: voiceToggleArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                const next = !notifCard.voiceOn;
                                                notifCard.voiceOn = next;
                                                notifCard.writeFile("notify-voice-enabled", notifCard.fmtBool(next));
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    width: parent.width
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 34
                                        radius: 8
                                        color: soundTestArea.containsMouse ? "#5D3FD3" : "#29233b"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "\uf028  PROBAR SONIDO"
                                            color: "white"
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        MouseArea {
                                            id: soundTestArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                soundTest.command = ["bash", "-c", "pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga"];
                                                soundTest.running = false;
                                                soundTest.running = true;
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: "Campana + resumen (Groq) al terminar cada sesión"
                                    color: "#6c7086"
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            Process { id: soundTest; command: ["true"]; running: false }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    implicitHeight: detailCol.implicitHeight + 32
                    radius: 18
                    color: "#e60d0d12"
                    border.color: "#383847"
                    border.width: 1
                    visible: widgetMenu.monitorDetail !== ""
                    opacity: widgetMenu.monitorDetail !== "" ? 1 : 0
                    scale: widgetMenu.monitorDetail !== "" ? 1 : 0.94
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
                                text: "\uf060  DETALLE  /  " + widgetMenu.monitorDetail.toUpperCase()
                                color: "#cba6f7"
                                font.family: root.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 1.5
                                Layout.fillWidth: true
                                MouseArea { id: detailBackArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: widgetMenu.monitorDetail = "" }
                            }
                        }

                        Text {
                            width: parent.width
                            text: widgetMenu.monitorDetail === "cpu" ? "Procesador, temperatura y uso por hilo l\u00f3gico" : widgetMenu.monitorDetail === "gpu" ? "Uso, memoria, temperatura y consumo NVIDIA" : widgetMenu.monitorDetail === "ram" ? "Memoria disponible y procesos con mayor consumo" : "Carga general, almacenamiento y sesi\u00f3n"
                            color: "#9a9aa7"
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: widgetMenu.monitorDetail === "cpu" ? [["USO", Math.round(widgetMenu.cpuUsage) + "%"], ["TEMPERATURA M\u00c1XIMA", Math.round(widgetMenu.cpuTemp) + " \u00b0C"], ["CARGA 1 MIN", widgetMenu.systemLoad], ["N\u00daCLEOS", "Detectados por kernel"]] : widgetMenu.monitorDetail === "gpu" ? [["USO GPU", Math.round(widgetMenu.gpuUsage) + "%"], ["TEMPERATURA", Math.round(widgetMenu.gpuTemp) + " \u00b0C"], ["MEMORIA", Math.round(widgetMenu.gpuMemory) + " / " + Math.round(widgetMenu.gpuMemoryTotal) + " MB"], ["CONSUMO", Math.round(widgetMenu.gpuPower) + " / " + Math.round(widgetMenu.gpuPowerLimit) + " W"]] : [["DISCO /", widgetMenu.rootDisk + "% usado"], ["CARGA", widgetMenu.systemLoad], ["TIEMPO ENCENDIDO", widgetMenu.systemUptime]]
                            delegate: Rectangle {
                                required property var modelData
                                width: widgetMenu.implicitWidth - 32
                                height: 42
                                radius: 7
                                color: "#1d1d26"
                                visible: widgetMenu.monitorDetail !== "ram" && widgetMenu.monitorDetail !== "cpu"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    Text { text: modelData[0]; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 11; Layout.fillWidth: true }
                                    Text { text: modelData[1]; color: "white"; font.family: root.fontFamily; font.pixelSize: 12; font.bold: true }
                                }
                            }
                        }

                        Text {
                            text: "PROCESOS RAM"
                            color: "#9a9aa7"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                            visible: widgetMenu.monitorDetail === "ram"
                        }
                        Repeater {
                            model: ramCard.processes
                            delegate: RowLayout {
                                width: widgetMenu.implicitWidth - 32
                                visible: widgetMenu.monitorDetail === "ram"
                                Text { text: processName; color: "white"; font.family: root.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: memory + " MB"; color: "#cba6f7"; font.family: root.fontFamily; font.pixelSize: 9 }
                            }
                        }

                        Text { text: "USO POR HILO L\u00d3GICO"; color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 10; font.bold: true; visible: widgetMenu.monitorDetail === "cpu" }
                        Grid {
                            columns: 4
                            columnSpacing: 6
                            rowSpacing: 6
                            width: parent.width
                            visible: widgetMenu.monitorDetail === "cpu"
                            Repeater {
                                model: widgetMenu.cpuThreads
                                delegate: Rectangle {
                                    required property string threadName
                                    required property string threadUsage
                                    width: (widgetMenu.implicitWidth - 50) / 4
                                    height: 38
                                    radius: 6
                                    color: "#1d1d26"
                                    Column {
                                        anchors.centerIn: parent
                                        Text { text: threadName.toUpperCase(); color: "#9a9aa7"; font.family: root.fontFamily; font.pixelSize: 9; anchors.horizontalCenter: parent.horizontalCenter }
                                        Text { text: Math.round(parseFloat(threadUsage)) + "%"; color: "#89b4fa"; font.family: root.fontFamily; font.pixelSize: 11; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                    }
                                }
                            }
                        }

                        Text { text: "Actualizaci\u00f3n autom\u00e1tica cada 2.5 s"; color: "#6c7086"; font.family: root.fontFamily; font.pixelSize: 9 }
                    }
                }
            }
        }
    }
    // ── Modo juegos — overlay fullscreen (dentro de root) ───────
    Rectangle {
        id: gameModeFade
        anchors.fill: parent
        color: "transparent"
        opacity: (root.gameShown && !root.gameClosing) ? 1 : 0
        // Bloquear el input de lo que haya detrás mientras el overlay está arriba.
        MouseArea {
            anchors.fill: parent
            enabled: root.gameModeActive
        }
    
        Rectangle {
            anchors.fill: parent
            color: "#ff0d0d12"
        }
    
        Text {
            anchors.top: parent.top
            anchors.topMargin: 56
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\uf11b  MODO JUEGOS"
            color: "#cba6f7"
            font.family: root.fontFamily
            font.pixelSize: 22
            font.bold: true
            font.letterSpacing: 8
        }
    
        Rectangle {
            id: gameCard
            width: 440
            height: gameConfirmCol.implicitHeight + 44
            visible: !root.gameLaunching
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 14
            radius: 16
            color: "#e60d0d12"
            border.color: "#383847"
            border.width: 1
    
            Column {
                id: gameConfirmCol
                anchors.fill: parent
                anchors.margins: 22
                spacing: 8
    
                Text {
                    text: "CERRAR APLICACIONES"
                    color: "#9a9aa7"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 3
                }
    
                Text {
                    width: parent.width
                    text: "Se cierran las demás apps para liberar recursos. Discord, WhatsApp y Spotify se quedan abiertas."
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
    
                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 8
                    color: gameSiArea.containsMouse ? "#e06c75" : "#55232a"
                    Text {
                        anchors.centerIn: parent
                        text: "SÍ, CERRAR Y JUGAR"
                        color: "white"
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: gameSiArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.gameConfirmClose()
                    }
                }
    
                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 8
                    color: gameNoArea.containsMouse ? "#5D3FD3" : "#262633"
                    Text {
                        anchors.centerIn: parent
                        text: "NO, SOLO ABRIR"
                        color: "#cdd6f4"
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: gameNoArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.gameConfirmNoClose()
                    }
                }
    
                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 8
                    color: gameCancelArea.containsMouse ? "#454554" : "#262633"
                    Text {
                        anchors.centerIn: parent
                        text: "CANCELAR"
                        color: "#cdd6f4"
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: gameCancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.gameCancel()
                    }
                }
            }
        }
    
        Item {
            anchors.fill: parent
            visible: root.gameLaunching

            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 20
                spacing: 18

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\uf11b"
                    color: "#cba6f7"
                    font.family: root.fontFamily
                    font.pixelSize: 64
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 420; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "CARGANDO JUEGOS…"
                    color: "#cdd6f4"
                    font.family: root.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                    font.letterSpacing: 6
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Steam y Cartridges están abriéndose"
                    color: "#9a9aa7"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                }
            }
        }
    
        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 44
            anchors.horizontalCenter: parent.horizontalCenter
            text: "El botón PS del volante también abre y cierra este modo"
            color: "#6f6f7b"
            font.family: root.fontFamily
            font.pixelSize: 11
        }
    }
}
