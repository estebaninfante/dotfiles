import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Mapa en vivo de las yemas de los 5 dedos que ve vision-hub, para las DOS
// manos a la vez: izquierda en azul, derecha en rojo.
//
// vision-hub publica una línea JSON por muestra en un socket Unix:
//   {"v":1,"n":12,"p":1,"hands":[
//      {"h":"Left","ok":1,"t":[[x,y],...5]},
//      {"h":"Right","ok":1,"t":[[x,y],...5]}]}
//   {"v":1,"n":13,"p":0}                  // no hay manos
//
// El lado y las coordenadas ya vienen resueltos por el motor (espejadas para
// la cámara frontal); acá sólo se escalan a la pantalla.
//
// Es solo lectura: `mask: Region {}` deja pasar todos los clics. La ventana se
// muestra únicamente mientras hay manos, así no queda una capa transparente
// encima del escritorio cuando no se usa.
//
// Optimización: un socket (sin procesos ni polling), 5 rectángulos chicos por
// mano y una interpolación corta. El latido `n` apaga el overlay si el
// pipeline se cuelga.
Item {
  id: root

  readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
    + "/vision-hub-hand.sock"

  property bool present: false
  property var tipsL: []
  property var tipsR: []
  property bool okL: true
  property bool okR: true
  property var headTip: null         // [x, y] del puntero de cabeza, o null
  property var targetTip: null       // [x, y] de la diana del entrenamiento, o null
  property int lastSeq: -1
  property real lastFresh: 0         // Date.now() del último `n` nuevo

  readonly property real dotSize: 30

  function handleLine(line) {
    var msg
    try {
      msg = JSON.parse(line)
    } catch (e) {
      return
    }
    if (!msg || msg.v !== 1) return
    if (msg.p !== 1) {
      // No se borran las puntas: al volver la mano, los círculos salen desde
      // donde estaban en vez de saltar desde la esquina.
      if (root.present) root.present = false
      return
    }
    // Si el shell se reengancha a mitad de una mano, `n` puede coincidir con el
    // último visto: la primera muestra se acepta igual.
    if (msg.n === root.lastSeq && root.present) return
    root.lastSeq = msg.n
    root.lastFresh = Date.now()

    var hands = msg.hands || []
    var left = []
    var right = []
    var blockedLeft = false
    var blockedRight = false
    for (var i = 0; i < hands.length; i++) {
      var hand = hands[i]
      if (!hand || !hand.t || hand.t.length < 5) continue
      if (hand.h === "Right") {
        right = hand.t
        blockedRight = hand.ok === 0
      } else {
        left = hand.t            // "Left" o sin dato de lado -> azul
        blockedLeft = hand.ok === 0
      }
    }
    root.tipsL = left
    root.tipsR = right
    root.okL = !blockedLeft
    root.okR = !blockedRight
    root.headTip = (Array.isArray(msg.head) && msg.head.length >= 2)
      ? msg.head : null
    root.targetTip = (Array.isArray(msg.target) && msg.target.length >= 2)
      ? msg.target : null
    root.present = left.length > 0 || right.length > 0
      || root.headTip !== null || root.targetTip !== null
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
      if (Date.now() - root.lastFresh > 1200) root.present = false
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

      delegate: HandDot {
        required property int index

        tip: root.tipsL[index] !== undefined ? root.tipsL[index] : null
        side: "Left"
        dim: !root.okL
        screenW: panel.width
        screenH: panel.height
        dotSize: root.dotSize
      }
    }

    Repeater {
      model: 5

      delegate: HandDot {
        required property int index

        tip: root.tipsR[index] !== undefined ? root.tipsR[index] : null
        side: "Right"
        dim: !root.okR
        screenW: panel.width
        screenH: panel.height
        dotSize: root.dotSize
      }
    }

    HeadPointer {
      tip: root.headTip
      screenW: panel.width
      screenH: panel.height
    }

    TargetBall {
      tip: root.targetTip
      screenW: panel.width
      screenH: panel.height
    }
  }
}
