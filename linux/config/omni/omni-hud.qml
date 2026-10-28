// omni-hud — la superficie en pantalla de Omni.
//
// Una tarjeta abajo al centro, mínima: qué está haciendo (escuchando, pensando,
// hablando), lo que entendió y lo que responde. Se muestra sola cuando hay
// actividad y se va sola cuando terminó: no hay ventana que abrir ni cerrar.
//
// Lee ~/.local/state/omni/status.json, que escribe `omni` en cada paso:
//   {state, level, updatedAt, activity:{transcript, result, say}, ...}
//
// Se corre standalone: quickshell --no-duplicate -p omni-hud.qml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    readonly property string statusPath: (Quickshell.env("HOME") || "") + "/.local/state/omni/status.json"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int lingerMs: 5000
    readonly property int staleMs: 15000

    property var snap: ({})
    property string state: "idle"
    property double lastUpdate: 0
    property double lastEventAt: 0
    property int tick: 0

    readonly property string transcript: (snap.activity && snap.activity.transcript) || ""
    readonly property string result: (snap.activity && snap.activity.result)
        || (snap.activity && snap.activity.say) || ""

    readonly property bool working: state === "listening" || state === "thinking"
        || state === "acting" || state === "error"
    readonly property bool stale: lastUpdate === 0 || (Date.now() - lastUpdate) > staleMs
    readonly property bool recent: lastEventAt > 0 && (Date.now() - lastEventAt) < lingerMs
    readonly property bool show: tick >= 0 && !stale && (working || recent)

    readonly property color tint: state === "listening" ? "#94e2d5"
        : state === "thinking" ? "#fab387"
        : state === "acting" ? "#cba6f7"
        : state === "error" ? "#f38ba8"
        : state === "done" ? "#a6e3a1"
        : "#89b4fa"

    readonly property string etiqueta: state === "listening" ? "Escuchando"
        : state === "thinking" ? "Pensando"
        : state === "acting" ? "Haciendo"
        : state === "error" ? "No entendí"
        : state === "done" ? "Omni"
        : "Omni"

    function aplicar(texto) {
        let parsed = null
        try {
            parsed = JSON.parse(texto)
        } catch (err) {
            return
        }
        if (!parsed || typeof parsed !== "object") return
        root.snap = parsed
        root.state = typeof parsed.state === "string" ? parsed.state : "idle"
        root.lastUpdate = Number(parsed.updatedAt) || Date.now()
        if (root.state !== "idle") root.lastEventAt = Date.now()
    }

    Process {
        id: lector
        command: ["bash", "-lc", "cat \"" + root.statusPath + "\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.aplicar(this.text)
        }
    }

    Timer {
        interval: root.working ? 200 : 700
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.tick++
            lector.running = false
            lector.running = true
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: cuerpo.implicitHeight + 24
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "omni-hud"
            mask: Region {}
            visible: root.show

            Rectangle {
                id: tarjeta
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 48, 640)
                height: cuerpo.implicitHeight + 24
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.9)
                border.color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 1

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    height: 2
                    radius: 1
                    color: root.tint
                    opacity: 0.8
                }

                ColumnLayout {
                    id: cuerpo
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: root.tint
                            opacity: root.state === "thinking" ? 0.5 : 1
                            SequentialAnimation on opacity {
                                running: root.state === "thinking" || root.state === "listening"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }

                        Text {
                            text: root.etiqueta
                            color: root.tint
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "LFM3-Omni-2B"
                            color: "#666677"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.transcript.length > 0
                        text: root.transcript
                        color: "#aaaaaa"
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.result.length > 0
                        text: root.result
                        color: "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
