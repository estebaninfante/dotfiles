import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

// Launcher (reemplazo de rofi). Fuente de datos + arranque en LaunchService.
// Tabs de modo, búsqueda, lista de resultados y menú contextual
// (Shift+Enter, paridad con rofi-context-menu).
// FloatingWindow (toplevel wayland normal, tipo rofi): sin layer-shell ni grab
// de teclado fullscreen (el grab al cerrar dejaba el teclado en estado raro).
// Se abre por keybind/IPC sin input previo del panel; la flotación/centrado
// viene de la windowrule en hyprland.lua (title: quickshell-launcher).
FloatingWindow {
    id: launcher
    title: "quickshell-launcher"
    visible: UIState.launcherOpen
    color: "transparent"
    implicitWidth: cardW
    implicitHeight: launcherCol.implicitHeight + 2

    property bool contextActive: false
    property var contextTarget: null
    property var contextActions: []
    property int currentIndex: 0
    property int ctxIndex: 0

    readonly property int cardW: 560
    readonly property int headerH: 44
    readonly property int inputH: 44
    readonly property int footerH: 26
    readonly property int listH: Math.min(Math.max(LaunchService.results.length, 1) * 42, 328)
    readonly property int ctxH: Math.min(Math.max(contextActions.length, 1) * 38, 260)

    readonly property var modeTabs: [["apps", "APLICACIONES"], ["files", "ARCHIVOS"], ["scripts", "SCRIPTS"]]

    onVisibleChanged: {
        if (!visible && UIState.launcherOpen) UIState.launcherOpen = false;
    }
    Connections {
        target: UIState
        function onLauncherOpenChanged() {
            if (UIState.launcherOpen) {
                currentIndex = 0;
                ctxIndex = 0;
                input.text = "";
                input.forceActiveFocus();
            } else {
                contextActive = false;
                contextTarget = null;
                UIState.hoversReset();
            }
        }
        function onLauncherModeChanged() {
            if (UIState.launcherOpen) input.text = "";
        }
    }

    function navigate(delta) {
        if (contextActive) {
            var total = contextActions.length + 1;
            ctxIndex = (ctxIndex + delta + total) % total;
        } else {
            var n = LaunchService.results.length;
            if (n > 0) currentIndex = (currentIndex + delta + n) % n;
        }
    }

    function cycleMode(delta) {
        var order = ["apps", "files", "scripts"];
        var i = order.indexOf(UIState.launcherMode);
        UIState.launcherMode = order[(i + delta + order.length) % order.length];
        currentIndex = 0;
    }

    function activate() {
        if (contextActive) {
            if (ctxIndex === 0) return closeContext();
            return contextExec(ctxIndex - 1);
        }
        var item = LaunchService.results[currentIndex];
        if (item !== undefined) LaunchService.launch(item);
    }

    function openContext() {
        if (contextActive) return;
        var item = LaunchService.results[currentIndex];
        if (item === undefined || item.kind === "app") return;
        contextTarget = item;
        contextActions = buildContext(item);
        ctxIndex = 1;
        contextActive = true;
    }

    function closeContext() {
        contextActive = false;
        contextTarget = null;
        ctxIndex = 0;
        input.forceActiveFocus();
    }

    function buildContext(item) {
        var t = item.path;
        var acts = [];
        if (item.isDir) {
            acts.push({ label: "📂 Abrir carpeta en Gestor de Archivos", args: ["xdg-open", t] });
            acts.push({ label: "💻 Abrir carpeta en Terminal (Kitty)", args: ["kitty", "-d", t] });
            acts.push({ label: "📝 Abrir carpeta en Neovim", args: ["kitty", "-d", t, "-e", "nvim", "."] });
            acts.push({ label: "📋 Copiar ruta al portapapeles", copy: t });
        } else {
            acts.push({ label: "📄 Abrir archivo con aplicación por defecto", args: ["xdg-open", t] });
            if (item.isExec)
                acts.push({ label: "🚀 Ejecutar script", args: [t] });
            acts.push({ label: "💻 Abrir carpeta contenedora en Terminal (Kitty)", args: ["kitty", "-d", item.dir] });
            acts.push({ label: "📁 Mostrar carpeta en Gestor de Archivos", args: ["xdg-open", item.dir] });
            acts.push({ label: "📝 Abrir archivo en Neovim", args: ["kitty", "-d", item.dir, "-e", "nvim", t] });
            acts.push({ label: "📋 Copiar ruta al portapapeles", copy: t });
        }
        return acts;
    }

    function contextExec(index) {
        var act = contextActions[index];
        if (act === undefined) return;
        if (act.args) LaunchService.run(act.args);
        else LaunchService.copyToClipboard(act.copy);
        contextActive = false;
        contextTarget = null;
        UIState.launcherOpen = false;
    }

    function iconFor(item) {
        if (item.kind === "file") return item.isDir ? "\uf07b" : "\uf15b";
        if (item.kind === "script") return "\uf120";
        if (item.kind === "app") return "\uf108";
        return "";
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Theme.bg
        border.color: Theme.border
        border.width: 1

        Column {
            id: launcherCol
            anchors.fill: parent

            // ── Tabs de modo ────────────────────────────────────
            Rectangle {
                width: parent.width
                height: launcher.headerH
                radius: 15
                color: Theme.bg

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    Repeater {
                        model: launcher.modeTabs
                        delegate: Rectangle {
                            required property var modelData
                            property bool active: UIState.launcherMode === modelData[0]
                            width: Math.max(90, tabLabel.implicitWidth + 22)
                            height: parent.height - 14
                            Layout.alignment: Qt.AlignVCenter
                            radius: 9
                            color: active ? Theme.fg : tabArea.containsMouse ? Theme.bgHover : Theme.bgItem

                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: modelData[1]
                                color: active ? Theme.fgOnWhite : Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.pixelSmall
                                font.bold: true
                            }

                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    UIState.launcherMode = modelData[0];
                                    launcher.currentIndex = 0;
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: closeLauncher
                        width: 30
                        height: parent.height - 14
                        Layout.alignment: Qt.AlignVCenter
                        radius: 9
                        color: closeLauncherArea.containsMouse ? Theme.bgItem : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            color: Theme.fgFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.pixelNormal
                        }
                        MouseArea {
                            id: closeLauncherArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: UIState.launcherOpen = false
                        }
                    }
                }
            }

            // ── Búsqueda ───────────────────────────────────────
            Rectangle {
                width: parent.width
                height: launcher.inputH
                color: Theme.bg

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf002"
                        color: Theme.fgFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelNormal
                    }

                    TextInput {
                        id: input
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 40
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelLarge
                        selectByMouse: true
                        clip: true
                        onTextChanged: {
                            LaunchService.query = text;
                            LaunchService.updateSearch();
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.text.length === 0
                            text: "Busca aplicaciones, archivos o scripts…"
                            color: Theme.fgDimmer
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.pixelLarge
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) { launcher.navigate(1); event.accepted = true; }
                            else if (event.key === Qt.Key_Up) { launcher.navigate(-1); event.accepted = true; }
                            else if (event.key === Qt.Key_Left) {
                                if (!launcher.contextActive) launcher.cycleMode(-1);
                                event.accepted = true;
                            }
                            else if (event.key === Qt.Key_Right) {
                                if (!launcher.contextActive) launcher.cycleMode(1);
                                event.accepted = true;
                            }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (event.modifiers & Qt.ShiftModifier)
                                    launcher.openContext();
                                else
                                    launcher.activate();
                                event.accepted = true;
                            }
                            else if (event.key === Qt.Key_Escape) {
                                if (launcher.contextActive) launcher.closeContext();
                                else UIState.launcherOpen = false;
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            // ── Resultados / contexto ──────────────────────────
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            ListView {
                id: resultsList
                width: parent.width
                height: Math.max(launcher.listH, 60)
                visible: !launcher.contextActive
                model: LaunchService.results
                clip: true
                currentIndex: launcher.currentIndex

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: resultsList.width
                    height: 40
                    radius: 8
                    color: index === launcher.currentIndex ? Theme.fg : rowArea.containsMouse ? Theme.bgHover : Theme.bg

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 10

                        Item {
                            width: 20
                            height: parent.height
                            Text {
                                anchors.centerIn: parent
                                text: launcher.iconFor(modelData)
                                color: index === launcher.currentIndex ? Theme.fgOnWhite : Theme.fgFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.pixelNormal
                            }
                        }

                        Column {
                            width: parent.width - 42
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                width: parent.width
                                text: modelData.name
                                elide: Text.ElideRight
                                color: index === launcher.currentIndex ? Theme.fgOnWhite : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.pixelLarge
                            }
                            Text {
                                width: parent.width
                                visible: modelData.sub !== undefined && modelData.sub !== ""
                                text: modelData.sub || ""
                                elide: Text.ElideRight
                                color: index === launcher.currentIndex ? "#999999" : Theme.fgFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.pixelSmall
                            }
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.currentIndex = index
                        onClicked: LaunchService.launch(modelData)
                    }
                }

                Item {
                    anchors.centerIn: parent
                    visible: LaunchService.results.length === 0
                    Text {
                        anchors.centerIn: parent
                        text: LaunchService.loading ? "Cargando…" : "Sin resultados"
                        color: Theme.fgDimmer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelNormal
                    }
                }
            }

            ListView {
                id: ctxList
                width: parent.width
                height: Math.max(launcher.ctxH, 60)
                visible: launcher.contextActive
                clip: true

                model: [
                    { label: "⬅ Volver a resultados", back: true },
                    ...launcher.contextActions
                ]

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ctxList.width
                    height: 38
                    radius: 8
                    color: index === launcher.ctxIndex ? Theme.fg : rowArea.containsMouse ? Theme.bgHover : Theme.bg

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !modelData.back
                        text: modelData.label
                        elide: Text.ElideRight
                        width: parent.width - 24
                        color: index === launcher.ctxIndex ? Theme.fgOnWhite : Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelNormal
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.back
                        text: modelData.label
                        elide: Text.ElideRight
                        width: parent.width - 24
                        color: index === launcher.ctxIndex ? Theme.fgOnWhite : Theme.fgDimmer
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.pixelNormal
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.ctxIndex = index
                        onClicked: {
                            if (modelData.back) launcher.closeContext();
                            else launcher.contextExec(launcher.contextActions.indexOf(modelData));
                        }
                    }
                }
            }

            // ── Footer ─────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: launcher.footerH
                color: Theme.bg
                Text {
                    anchors.centerIn: parent
                    text: launcher.contextActive ? "↑↓ mover · Enter ejecutar · Esc volver" : "↑↓ mover · Enter abrir · Shift+Enter opciones · Esc cerrar"
                    color: Theme.fgDimmer
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.pixelSmall
                }
            }
        }
    }
}