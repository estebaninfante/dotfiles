import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Mapa en vivo de las yemas de los 5 dedos que ve vision-hub.
//
// vision-hub publica una línea JSON por muestra en un socket Unix:
//   {"v":1,"n":12,"p":1,"ok":1,"t":[[x,y],...5]}
//   {"v":1,"n":13,"p":0}                  // no hay mano
//
// `t` son las puntas (pulgar, índice, medio, anular, meñique) normalizadas y ya
// espejadas por vision-hub: acá sólo se escalan a la pantalla.
//
// Es solo lectura: `mask: Region {}` deja pasar todos los clics. La ventana se
// muestra únicamente mientras hay mano, así no queda una capa transparente
// encima del escritorio cuando no se usa.
//
// Optimización: un socket (sin procesos ni polling), 30 Hz como máximo, 5
// rectángulos chicos y sin animaciones intermedias (los landmarks ya vienen
// suavizados). El latido `n` apaga el overlay si el pipeline se cuelga.
Item {
  id: root

  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
    + "/vision-hub-hand.sock"

  property bool present: false
  property bool blocked: false       // mano sobre la cara u otra compuerta
  property string hand: ""           // "L" izquierda | "R" derecha | "" sin dato
  property var tips: []
  property int lastSeq: -1
  property real lastFresh: 0         // Date.now() del último `n` nuevo

  // Diámetro de la yema, un poco más grande en pantallas con escala alta.
  readonly property real dotSize: 30

  // Cámara frontal: mano IZQUIERDA en azul, DERECHA en rojo. Sin dato de lado,
  // se mantiene el azul (el pedido original).
  readonly property color dotColor: root.hand === "R"
    ? Qt.rgba(0.95, 0.30, 0.30, 0.45)
    : Qt.rgba(0.29, 0.56, 0.95, 0.45)
  readonly property color dotBorder: root.hand === "R"
    ? Qt.rgba(1.0, 0.62, 0.62, 0.55)
    : Qt.rgba(0.60, 0.78, 1.0, 0.55)

  function handleLine(line) {
    var msg
    try {
      msg = JSON.parse(line)
    } catch (e) {
      return
    }
    if (!msg || msg.v !== 1) return
    if (msg.p !== 1) {
      if (root.present) {
        root.present = false
        root.tips = []
        root.hand = ""
      }
      return
    }
    // Si el shell se reengancha a mitad de una mano, `n` puede coincidir con el
    // último visto: la primera muestra se acepta igual.
    if (msg.n === root.lastSeq && root.present) return
    root.lastSeq = msg.n
    root.lastFresh = Date.now()
    root.blocked = msg.ok === 0
    root.hand = msg.h === "L" || msg.h === "R" ? msg.h : ""
    root.tips = msg.t || []
    root.present = root.tips.length > 0
  }

  // Limpia el socket de una corrida anterior y recién ahí escucha: un
  // quickshell que se reinicia deja el archivo atrás.
  Process {
    id: limpiar
    running: true
    command: ["rm", "-f", root.socketPath]
    onExited: server.active = true
  }

  SocketServer {
    id: server
    active: false
    path: root.socketPath
    handler: Socket {
      parser: SplitParser {
        onRead: line => root.handleLine(line)
      }
    }
  }

  // Si deja de llegar un `n` nuevo, algo se colgó: se apaga solo.
  Timer {
    interval: 400
    running: root.present
    repeat: true
    onTriggered: {
      if (Date.now() - root.lastFresh > 1200) {
        root.present = false
        root.tips = []
      }
    }
  }

  PanelWindow {
    id: panel

    visible: root.present
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "vision-hub-hands"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Repeater {
      model: 5

      delegate: Rectangle {
        required property int index

        readonly property var tip: root.tips[index]

        visible: root.present && root.tips.length > index
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        antialiasing: true
        color: root.blocked
          ? Qt.rgba(root.hand === "R" ? 0.95 : 0.29,
                    root.hand === "R" ? 0.30 : 0.56,
                    root.hand === "R" ? 0.30 : 0.95, 0.20)
          : root.dotColor
        border.width: 1
        border.color: root.blocked
          ? Qt.rgba(root.dotBorder.r, root.dotBorder.g, root.dotBorder.b, 0.25)
          : root.dotBorder

        x: (tip ? tip[0] : 0) * panel.width - width / 2
        y: (tip ? tip[1] : 0) * panel.height - height / 2
      }
    }
  }
}
