// dictado-overlay — la píldora del dictado. Nada más.
//
// Una cápsula flotante al pie con una matriz de puntos que sigue tu voz y el
// tiempo que llevás. Mientras se transcribe pasa a "pensando…" en el mismo
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
    property var ondas: []
    readonly property int ondasMax: 24
    readonly property int filas: 13
    readonly property int medio: (filas - 1) / 2
    readonly property real pasoX: 4
    readonly property real pasoY: 2
    // Un bloque de audio cada 100 ms (= ritmo de `dictado`). La matriz es un
    // buffer circular por tiempo, no por "cuando cambió el nivel": si se
    // empujaba una muestra sólo al cambiar la propiedad, los silencios
    // congelaban la onda y las repeticiones llenaban la ventana de columnas
    // idénticas (eso era lo que se veía como rectángulos).
    readonly property int muestreoMs: 100
    property real nivelSuave: 0

    // Filas encendidas a cada lado del centro (0..6 → 1..13 filas totales).
    // El RMS de `dictado` vive casi todo entre 0.05 y 0.35: el mapa es
    // perceptual (raíz) y satura recién con voz fuerte. Un mapa lineal
    // (n*13) aplastaba la mayoría de los bloques en el mismo escalón, que es
    // lo que se veía como "rectángulos".
    function filasEncendidas(nivel) {
        const n = Math.min(1, Math.max(0, nivel || 0))
        if (n <= 0.012) return 0
        return Math.max(1, Math.min(medio, Math.round(medio * Math.pow(Math.min(1, n / 0.40), 0.55))))
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

    // Envolvente con ataque instantáneo y caída suave. Sin esto, un bloque de
    // silencio en medio de una palabra abre un hueco de una columna y la línea
    // "se desconecta". Se llama una vez por tick, así que el buffer avanza
    // siempre al mismo ritmo aunque el nivel no cambie.
    function muestrear() {
        const n = root.grabando ? root.nivel : 0
        root.nivelSuave = n > root.nivelSuave ? n : root.nivelSuave * 0.72
        const nuevo = root.ondas.slice()
        nuevo.push(root.nivelSuave)
        while (nuevo.length > root.ondasMax) nuevo.shift()
        root.ondas = nuevo
    }

    // Lee `estado.json` (lo escribe `dictado`) y vuelca el estado al overlay.
    // `dictado` trunca y reescribe el archivo 10 veces por segundo: una lectura
    // que cae en medio queda vacía o a medias. Eso NO significa "se terminó el
    // dictado", así que se ignora y el estado anterior sigue valiendo; la
    // caducidad por `actualizado` apaga la píldora sólo si el grabador muere.
    function aplicarEstado(texto) {
        let nuevo = null
        try {
            nuevo = JSON.parse(texto || "{}")
        } catch (err) {
            return
        }
        if (!nuevo || typeof nuevo.actualizado !== "number") return
        root.ahora = Date.now()
        root.estado = typeof nuevo.estado === "string" ? nuevo.estado : "idle"
        root.microfono = typeof nuevo.microfono === "string" ? nuevo.microfono : ""
        root.nivel = typeof nuevo.nivel === "number" ? nuevo.nivel : 0
        root.desde = Number(nuevo.desde) || 0
        root.actualizado = nuevo.actualizado
    }

    // Sondeo liviano (10/s, el mismo ritmo al que escribe `dictado`) en vez de
    // un proceso por cuadro; el archivo puede desaparecer y volver, así que
    // `cat` es más robusto que un watcher.
    Process {
        id: lector
        command: ["sh", "-c", "cat \"$XDG_RUNTIME_DIR/dictado/estado.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.aplicarEstado(this.text)
        }
    }

    Timer {
        interval: root.muestreoMs
        running: true
        repeat: true
        onTriggered: {
            root.ahora = Date.now()
            root.muestrear()
            if (!lector.running) lector.running = true
        }
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
                    color: "#0a0a0c"
                    border.width: 1
                    border.color: "#2a2a30"
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
                            width: root.ondasMax * root.pasoX
                            height: root.filas * root.pasoY
                            anchors.verticalCenter: parent.verticalCenter

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                const columnas = root.ondasMax
                                const filas = root.filas
                                const pasoX = root.pasoX
                                const pasoY = root.pasoY
                                const centro = (filas - 1) / 2
                                for (let c = 0; c < columnas; c++) {
                                    // Mientras grabás siempre hay al menos la fila
                                    // central: un RMS bajo abre un hueco de una
                                    // columna y la línea parece cortada.
                                    const piso = root.grabando ? 1 : 0
                                    const encendidas = root.pensando ? 0
                                        : Math.max(piso, root.filasEncendidas(root.ondas[c]))
                                    for (let f = 0; f < filas; f++) {
                                        const encendido = encendidas > 0 && Math.abs(f - centro) <= encendidas
                                        ctx.globalAlpha = encendido ? 1 : 0.13
                                        ctx.fillStyle = "#ffffff"
                                        ctx.beginPath()
                                        ctx.arc(c * pasoX + pasoX / 2, f * pasoY + pasoY / 2, encendido ? 0.9 : 0.55, 0, Math.PI * 2)
                                        ctx.fill()
                                    }
                                }
                                ctx.globalAlpha = 1
                            }

                            Connections {
                                target: root
                                function onOndasChanged() { matriz.requestPaint() }
                                function onPensandoChanged() { matriz.requestPaint() }
                                function onGrabandoChanged() { matriz.requestPaint() }
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
