import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"

Rectangle {
    id: screenCard
    width: parent.width
    height: 360
    radius: 12
    color: "#000000"
    border.color: "#333"
    border.width: 1
    visible: UIState.activeSection === "pantallas"
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
        Text { text: "PANTALLAS"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.5 }
        Text { text: "Configura cómo usar cada monitor conectado"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 13 }
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
                color: "#000000"
                Column {
                    anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Text { text: name; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    Text { text: description; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight; width: 390 }
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
                    color: screenModeArea.containsMouse ? "white" : "#141414"
                    Text { anchors.centerIn: parent; text: modelData; color: screenModeArea.containsMouse ? "#000000" : "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 8; font.bold: true }
                    MouseArea { id: screenModeArea; anchors.fill: parent; hoverEnabled: true; onClicked: { if (screenCard.monitors.count) screenCard.apply(screenCard.monitors.get(screenCard.monitors.count - 1).name, modelData === "DUPLICAR" ? "duplicate" : modelData === "AMPLIAR" ? "extend" : modelData === "SOLO 2ª" ? "second" : "only"); } }
                }
            }
        }
        RowLayout {
            width: parent.width; spacing: 5
            Text { text: "POSICIÓN"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [["←", "left"], ["→", "right"], ["↑", "up"], ["↓", "down"]]
                delegate: Rectangle {
                    required property var modelData
                    width: 30; height: 28; radius: 7; color: positionArea.containsMouse ? "white" : "#141414"
                    Text { anchors.centerIn: parent; text: modelData[0]; color: positionArea.containsMouse ? "#000000" : "#aaa"; font.pixelSize: 14 }
                    MouseArea { id: positionArea; anchors.fill: parent; hoverEnabled: true; onClicked: { if (screenCard.monitors.count) screenCard.apply(screenCard.monitors.get(screenCard.monitors.count - 1).name, modelData[1]); } }
                }
            }
        }
        Text { text: screenCard.screenMessage || "Selecciona modo o mueve pantalla en pasos de 100 px"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
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