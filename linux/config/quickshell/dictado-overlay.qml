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
    property var ondas: []
    readonly property int ondasMax: 24
    readonly property int filas: 7
    readonly property real paso: 4

    // Cuántas filas de puntos se encienden a cada lado del centro. La ganancia
    // (×3) y la raíz hacen que la voz normal ya llene casi toda la matriz.
    function filasEncendidas(nivel) {
        const n = Math.min(1, Math.max(0, nivel || 0) * 3.0)
        return Math.round(Math.pow(n, 0.4) * (filas / 2))
    }

    readonly property bool fresco: actualizado > 0 && (ahora - actualizado) < 3000
    readonly property bool grabando: fresco && estado === "grabando"
    readonly property bool pensando: fresco && estado === "transcribiendo"
    readonly property bool visiblePildora: grabando || pensando

    readonly property string reloj: {
        if (!grabando || desde <= 0) return ""
        const s = Math.max(0, Math.floor((ahora - desde) / 1000))
        return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }

    onEstadoChanged: ultimoCambio = Date.now()
    onNivelChanged: {
        const nuevo = ondas.slice()
        nuevo.push(nivel)
        while (nuevo.length > ondasMax) nuevo.shift()
        ondas = nuevo
    }

    // FileView vigila el archivo: sin lanzar `cat` 8 veces por segundo.
    FileView {
        id: lector
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dictado/estado.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onTextChanged: {
            let nuevo = null
            try {
                nuevo = JSON.parse(lector.text() || "{}")
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

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: root.ahora = Date.now()
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
                    width: contenido.width + 26
                    height: 34
                    radius: 10
                    color: Qt.rgba(0.04, 0.04, 0.05, 0.94)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.09)
                    clip: true
                    opacity: root.visiblePildora ? 1 : 0
                    visible: opacity > 0.01
                    // Entra con fade y sale en el acto cuando dejás de dictar.
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    // Retícula tenue de puntos, como un panel LED.
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = "rgba(255,255,255,0.07)"
                            const paso = 5
                            for (let y = paso / 2; y < height; y += paso) {
                                for (let x = paso / 2; x < width; x += paso) {
                                    ctx.beginPath()
                                    ctx.arc(x, y, 0.8, 0, Math.PI * 2)
                                    ctx.fill()
                                }
                            }
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }

                    Row {
                        id: contenido
                        anchors.centerIn: parent
                        spacing: 10

                        // Onda en matriz de puntos: columnas de puntos encendidos
                        // simétricos respecto al centro.
                        Canvas {
                            id: matriz
                            width: root.ondasMax * root.paso
                            height: root.filas * root.paso
                            anchors.verticalCenter: parent.verticalCenter

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                const columnas = root.ondasMax
                                const filas = root.filas
                                const paso = root.paso
                                const centro = (filas - 1) / 2
                                for (let c = 0; c < columnas; c++) {
                                    const encendidas = root.pensando ? 0 : root.filasEncendidas(root.ondas[c])
                                    for (let f = 0; f < filas; f++) {
                                        const encendido = encendidas > 0 && Math.abs(f - centro) <= encendidas - 0.5
                                        ctx.globalAlpha = encendido ? 1 : 0.13
                                        ctx.fillStyle = "#ffffff"
                                        ctx.beginPath()
                                        ctx.arc(c * paso + paso / 2, f * paso + paso / 2, encendido ? 1.25 : 0.9, 0, Math.PI * 2)
                                        ctx.fill()
                                    }
                                }
                                ctx.globalAlpha = 1
                            }

                            Connections {
                                target: root
                                function onOndasChanged() { matriz.requestPaint() }
                                function onPensandoChanged() { matriz.requestPaint() }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pensando ? "pensando…" : root.reloj
                            color: root.pensando ? "#9aa3b5" : Qt.rgba(1, 1, 1, 0.92)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            font.letterSpacing: 0.5
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
