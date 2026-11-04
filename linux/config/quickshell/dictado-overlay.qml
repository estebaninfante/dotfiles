// dictado-overlay — la píldora del dictado. Nada más.
//
// Una cápsula flotante al pie con el punto rojo, las ondas que siguen tu voz y
// el tiempo que llevás. Mientras se transcribe pasa a "pensando…" en el mismo
// lugar; cuando termina desaparece.
//
// Lo publica `~/dotfiles/linux/bin/dictado` en
// ${XDG_RUNTIME_DIR}/dictado/estado.json:
//
//   {"estado": "grabando"|"transcribiendo"|"idle", "texto": "...",
//    "nivel": 0..1, "desde": epochMs, "actualizado": epochMs,
//    "microfono": "descripción del source de PipeWire"}   ← sólo grabando
//
// Click-through (mask vacío) y sin foco: no toca el teclado ni el mouse, y si
// el grabador muere la píldora se va sola (deja de refrescarse `actualizado`).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    property string estado: "idle"
    property string microfono: ""
    property real nivel: 0
    property double desde: 0
    property double actualizado: 0
    property double ahora: Date.now()
    property double ultimoCambio: 0
    property real nivelSuave: 0
    property var ondas: []
    readonly property int ondasMax: 28

    readonly property bool fresco: actualizado > 0 && (ahora - actualizado) < 3000
    readonly property bool grabando: fresco && estado === "grabando"
    readonly property bool pensando: fresco && estado === "transcribiendo"
    readonly property bool visiblePildora: grabando || pensando

    readonly property string reloj: {
        if (!grabando || desde <= 0) return ""
        const s = Math.max(0, Math.floor((ahora - desde) / 1000))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    onEstadoChanged: ultimoCambio = Date.now()
    onNivelChanged: {
        nivelSuave = nivelSuave * 0.6 + nivel * 0.4
        const nuevo = ondas.slice()
        nuevo.push(nivel)
        while (nuevo.length > ondasMax) nuevo.shift()
        ondas = nuevo
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: root.ahora = Date.now()
    }

    Process {
        id: lector
        command: ["sh", "-c", "cat \"$XDG_RUNTIME_DIR/dictado/estado.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let nuevo = null
                try {
                    nuevo = JSON.parse(this.text || "{}")
                } catch (err) {
                    nuevo = null
                }
                root.ahora = Date.now()
                if (!nuevo || typeof nuevo.actualizado !== "number") {
                    root.estado = "idle"
                    root.microfono = ""
                    root.nivel = 0
                    return
                }
                root.estado = typeof nuevo.estado === "string" ? nuevo.estado : "idle"
                root.microfono = typeof nuevo.microfono === "string" ? nuevo.microfono : ""
                root.nivel = typeof nuevo.nivel === "number" ? nuevo.nivel : 0
                root.desde = Number(nuevo.desde) || 0
                root.actualizado = nuevo.actualizado
            }
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: { if (!lector.running) lector.running = true }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            // Sólo la franja donde vive la cápsula: nada de bandas ni texto.
            anchors { bottom: true; left: true; right: true }
            implicitHeight: 96
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "dictado-overlay"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            visible: true

            Column {
                id: pila
                anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
                spacing: 4

                Rectangle {
                    id: pildora
                    width: contenido.width + 34
                    height: 42
                    radius: height / 2
                    color: Qt.rgba(0.06, 0.06, 0.07, 0.92)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                    opacity: root.visiblePildora ? 1 : 0
                    visible: opacity > 0.01
                    // Entra con fade y sale en el acto cuando dejás de dictar.
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Row {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 12

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: root.grabando ? "#f38ba8" : "#ffd866"
                            SequentialAnimation on opacity {
                                running: pildora.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            opacity: root.pensando ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Repeater {
                                model: root.ondasMax
                                Item {
                                    required property int index
                                    width: 3
                                    height: 24
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 3
                                        radius: 1.5
                                        color: "#94e2d5"
                                        opacity: 0.35 + 0.65 * (index / root.ondasMax)
                                        height: 3 + 20 * (root.ondas[index] || 0)
                                        Behavior on height { NumberAnimation { duration: 80 } }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pensando ? "pensando…" : root.reloj
                            color: root.pensando ? "#9aa3b5" : Qt.rgba(1, 1, 1, 0.85)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.features: { "tnum": 1 }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                // Qué micrófono está escuchando, en chiquito bajo la cápsula.
                // Siempre ocupa su renglón (opacity 0) para que la cápsula no
                // salte cuando aparece o desaparece al empezar/terminar.
                Text {
                    id: etiquetaMic
                    width: pildora.width
                    height: 12
                    text: "\uf130  " + root.microfono
                    opacity: (root.grabando && root.microfono !== "") ? 1 : 0
                    color: Qt.rgba(1, 1, 1, 0.38)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
