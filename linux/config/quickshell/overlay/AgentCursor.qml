import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

// AgentCursor — la flecha del puntero del asiento, sólo para el asiento.
//
// El puntero del agente nunca llega al compositor (el broker lo inyecta en la
// app), así que no hay cursor que ver. Esto dibuja uno simulado: una capa
// overlay por pantalla, transparente y click-through, en la posición que
// AgentCursorService lee del broker.
//
// Sólo aparece cuando la ventana apuntada está a la vista en ESTA pantalla. En
// la grilla el tile es una miniatura escalada del workspace, así que la flecha
// quedaría en el lugar equivocado: ahí el workspace del asiento no está activo y
// la capa se esconde sola.
Variants {
    id: raiz
    model: Quickshell.screens

    delegate: PanelWindow {
        required property var modelData

        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "agent-seat-cursor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        // `ipc` de la ventana del asiento que el agente acaba de apuntar, si está
        // en esta pantalla y a la vista; si no, null.
        readonly property var ventana: {
            const n = AgentCursorService.activo ? AgentCursorService.window : 0
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
                return ipc
            }
            return null
        }

        // Posición global del puntero = ventana + offset dentro de ella; la capa
        // se mide desde la esquina de su pantalla.
        readonly property real puntoX: ventana ? ventana.at[0] + AgentCursorService.x - modelData.x : 0
        readonly property real puntoY: ventana ? ventana.at[1] + AgentCursorService.y - modelData.y : 0

        visible: ventana !== null

        Canvas {
            id: flecha
            // La punta del dibujo cae exactamente en el punto publicado.
            x: parent.puntoX - 2
            y: parent.puntoY - 2
            width: 20
            height: 26
            // El overlay ocupa la pantalla entera: nada de esto recibe clicks.
            enabled: false

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
                ctx.fillStyle = String(Theme.fg)
                ctx.fill()
                ctx.lineWidth = 1.6
                ctx.lineJoin = "round"
                ctx.strokeStyle = String(Theme.bg)
                ctx.stroke()
            }

            Connections {
                target: Theme
                function onFgChanged() { flecha.requestPaint() }
            }
        }

        onPuntoXChanged: flecha.requestPaint()
        onPuntoYChanged: flecha.requestPaint()
    }
}
