pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// AgentCursorService — dónde apunta el puntero del asiento.
//
// El puntero del agente lo inyecta el broker del Agent Seat directo en la app:
// nunca llega al compositor, así que no hay cursor que dibujar. El broker sí
// sabe dónde está y lo publica en
//
//   ${XDG_RUNTIME_DIR}/omarchy/agent-seat/cursor.json
//   {"window": 1, "app": "chromium", "x": 350.0, "y": 200.0, "stamp": 1795480947.83}
//
// con x/y en píxeles LÓGICOS desde la esquina de la ventana. Esto solo lee ese
// archivo y lo traduce a una posición global usando la ventana de Hyprland
// (el broker no conoce la posición de la ventana en la pantalla).
//
// `window: 0` (o el archivo ausente) = no hay puntero que dibujar.
Singleton {
    id: servicio

    readonly property string ruta: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy/agent-seat/cursor.json"

    property int window: 0
    property real x: 0
    property real y: 0
    property double stamp: 0

    // Se descarta solo si el asiento se cerró con el archivo a medio escribir.
    property double ahora: Date.now()
    readonly property bool activo: window > 0 && (ahora - stamp * 1000) < 60000

    function leer() {
        const crudo = archivo.text()
        if (!crudo)
            return
        try {
            const dato = JSON.parse(crudo)
            servicio.window = Number(dato.window) || 0
            servicio.x = Number(dato.x) || 0
            servicio.y = Number(dato.y) || 0
            servicio.stamp = Number(dato.stamp) || 0
        } catch (e) {
            // Lectura a medias: se queda el último valor bueno.
        }
    }

    FileView {
        id: archivo
        path: servicio.ruta
        watchChanges: true
        printErrors: false
        onLoaded: servicio.leer()
        onFileChanged: {
            reload()
            servicio.leer()
        }
    }

    // Un reloj lento para que `activo` caiga solo cuando el asiento se cerró
    // sin borrar el archivo (el broker lo borra al cerrar la ventana).
    Timer {
        interval: 5000
        running: servicio.window > 0
        repeat: true
        onTriggered: servicio.ahora = Date.now()
    }
}
