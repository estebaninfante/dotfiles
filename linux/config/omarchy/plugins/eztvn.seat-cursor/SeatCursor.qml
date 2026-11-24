import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// SeatCursor — el cursor del Agent Seat, simulado.
//
// El puntero del agente lo inyecta el broker del asiento directo en la app
// (eventos de puntero sobre la superficie): nunca llega al compositor, así que
// no hay cursor que ver. Pero el broker sí sabe dónde está y lo publica en
//
//   ${XDG_RUNTIME_DIR}/omarchy/agent-seat/cursor.json
//   {"window": 1, "app": "chromium", "x": 350.0, "y": 200.0, "stamp": 1795480947.83}
//
// con x/y en píxeles LÓGICOS desde la esquina de la ventana (el broker no conoce
// la posición de la ventana en la pantalla; eso lo dice Hyprland). Con las dos
// cosas, la posición global es ventana.at + (x, y), y acá se dibuja la flecha.
//
// Sólo aparece cuando la ventana apuntada está a la vista en esa pantalla: en la
// grilla el tile es una miniatura escalada, así que la flecha mentiría y el
// workspace del asiento no está activo. Una capa por pantalla, transparente y
// click-through (`mask: Region {}`): no se come ningún clic.
Item {
    id: raiz

    // ---- estado que publica el broker -------------------------------------
    property int ventana: 0
    property real punteroX: 0
    property real punteroY: 0
    property double marca: 0
    property double ahora: Date.now()

    readonly property string archivo: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy/agent-seat/cursor.json"
    readonly property bool activo: ventana > 0 && (ahora - marca * 1000) < 60000

    function leer() {
        const crudo = cursor.text()
        if (!crudo)
            return
        try {
            const dato = JSON.parse(crudo)
            raiz.ventana = Number(dato.window) || 0
            raiz.punteroX = Number(dato.x) || 0
            raiz.punteroY = Number(dato.y) || 0
            raiz.marca = Number(dato.stamp) || 0
        } catch (e) {
            // Lectura a medias (el broker escribe y algo más lee): se queda lo último bueno.
        }
    }

    // El broker reescribe el archivo en cada movimiento del agente: sin polling.
    FileView {
        id: cursor
        path: raiz.archivo
        watchChanges: true
        printErrors: false
        onLoaded: raiz.leer()
        onFileChanged: {
            reload()
            raiz.leer()
        }
    }

    // Red de seguridad: si el asiento se cerró sin borrar el archivo, la flecha
    // se apaga sola en vez de quedarse pegada en una ventana que ya no existe.
    Timer {
        interval: 5000
        running: raiz.ventana > 0
        repeat: true
        onTriggered: raiz.ahora = Date.now()
    }

    // ---- el puntero, por pantalla -----------------------------------------
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData

            screen: modelData
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "agent-seat-cursor"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            // El `ipc` de Hyprland de la ventana apuntada, si está en esta
            // pantalla y a la vista; si no, null y la capa no se muestra.
            readonly property var apuntada: {
                const n = raiz.activo ? raiz.ventana : 0
                if (!n)
                    return null
                for (const t of Hyprland.toplevels) {
                    const ipc = t.lastIpcObject
                    if (!ipc || !ipc.class || !ipc.at)
                        continue
                    // El broker le pone a la clase del asiento su número: agent-<n>.<app>
                    const cual = /^agent-(\d+)\./.exec(ipc.class)
                    if (!cual || Number(cual[1]) !== n)
                        continue
                    if (!t.workspace || !t.workspace.active)
                        continue
                    // Cada pantalla dibuja sólo su parte del puntero.
                    if (ipc.monitor && modelData.name && ipc.monitor !== modelData.name)
                        continue
                    return ipc
                }
                return null
            }

            readonly property real puntoX: apuntada ? apuntada.at[0] + raiz.punteroX - modelData.x : 0
            readonly property real puntoY: apuntada ? apuntada.at[1] + raiz.punteroY - modelData.y : 0

            visible: apuntada !== null

            Canvas {
                id: flecha
                // La punta del dibujo cae exactamente en el punto publicado.
                x: parent.puntoX - 2
                y: parent.puntoY - 2
                width: 20
                height: 26
                enabled: false
                visible: parent.apuntada !== null

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.beginPath()
                    ctx.moveTo(2.5, 2)
                    ctx.lineTo(2.5, 21)
                    ctx.lineTo(7.5, 16)
                    ctx.lineTo(11, 23.5)
                    ctx.lineTo(14, 22)
                    ctx.lineTo(10.5, 14.5)
                    ctx.lineTo(17.5, 14)
                    ctx.closePath()
                    // Blanco con borde negro: se ve sobre cualquier ventana.
                    ctx.fillStyle = "#ffffff"
                    ctx.fill()
                    ctx.lineWidth = 1.6
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = "#000000"
                    ctx.stroke()
                }
            }

            onPuntoXChanged: flecha.requestPaint()
            onPuntoYChanged: flecha.requestPaint()
        }
    }
}
