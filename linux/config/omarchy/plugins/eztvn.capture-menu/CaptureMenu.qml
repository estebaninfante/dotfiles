import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// PrintScreen: congela la pantalla (PNG de capture-menu) y entra directo en la
// selección de región: al arrastrar el recuadro queda copiado. Un clic sobre
// una ventana la captura o graba (según Imagen/Grabar); un clic en el
// escritorio abre la barra (grabar pantalla/zona/ventana, capturar
// zona/ventana/pantalla). Shift+Print abre directo la barra.
//
// El recuadro vive en esta capa, así que no entra en la captura: el archivo se
// recorta del PNG original. Al grabar se manda geometría lógica y
// screenrecord-toggle filma sólo esa zona.
Item {
  id: root

  property bool opened: false
  property string selectionFile: ""
  property string doneFile: ""
  property string imagePath: ""
  property string mode: "menu" // "menu" | "region"
  property string intent: "image" // intención de la selección de región
  property int selectedIndex: 0

  property real dragX0: 0
  property real dragY0: 0
  property real dragX1: 0
  property real dragY1: 0
  property bool dragging: false
  property real pointerX: -1
  property real pointerY: -1

  // 0 = recién abierto, 1 = asentado. La barra y la pista entran con esto.
  property real reveal: 0

  readonly property real selX: Math.min(dragX0, dragX1)
  readonly property real selY: Math.min(dragY0, dragY1)
  readonly property real selW: Math.abs(dragX1 - dragX0)
  readonly property real selH: Math.abs(dragY1 - dragY0)

  readonly property var rows: [
    { key: "record",       icon: "󰻂", label: "Pantalla", caption: "grabar",   record: true },
    { key: "videoregion",  icon: "󰹵", label: "Zona",     caption: "grabar",   record: true },
    { key: "recordwindow", icon: "󰖲", label: "Ventana",  caption: "grabar",   record: true },
    { key: "region",       icon: "󰹵", label: "Zona",     caption: "capturar", record: false },
    { key: "window",       icon: "󰖲", label: "Ventana",  caption: "capturar", record: false },
    { key: "full",         icon: "󰹞", label: "Pantalla", caption: "capturar", record: false }
  ]

  Behavior on reveal {
    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
  }

  // El plugin queda cargado entre capturas (keepLoaded), así que las
  // coordenadas del recuadro sobreviven. Sin este reset, la siguiente captura
  // abriría mostrando la selección anterior como si ya estuviera elegida.
  function resetSelection() {
    root.dragX0 = 0
    root.dragY0 = 0
    root.dragX1 = 0
    root.dragY1 = 0
    root.dragging = false
    root.pointerX = -1
    root.pointerY = -1
  }

  function open(payloadJson) {
    var p = ({})
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { p = ({}) }
    root.selectionFile = String(p.selectionFile || "")
    root.doneFile = String(p.doneFile || "")
    root.imagePath = String(p.imagePath || "")
    // Print (imagen) abre directo en selección de región; Shift+Print (grabar)
    // abre la barra directamente.
    root.mode = String(p.defaultAction || "image") === "record" ? "menu" : "region"
    root.intent = "image"
    root.selectedIndex = 0
    root.resetSelection()
    root.reveal = 0
    root.opened = true
    Qt.callLater(function() {
      if (!root.opened) return
      root.reveal = 1
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    // El shell puede cerrar el panel (recarga, apagado): hay que dejar el
    // archivo de cancelación para que capture-menu suelte el lock al instante.
    root.finish(null)
  }

  function finish(key) {
    var selection = root.selectionFile
    var done = root.doneFile
    root.selectionFile = ""
    root.doneFile = ""
    if (done !== "") {
      if (key === null || key === undefined)
        resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(done)]
      else
        resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(key) + " > " + Util.shellQuote(selection) + "; : > " + Util.shellQuote(done)]
      resultProc.running = true
    } else {
      root.opened = false
    }
  }

  function move(delta) {
    if (root.rows.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.rows.length) % root.rows.length
  }

  function chooseRegion(kind) {
    root.mode = "region"
    root.intent = kind
    root.resetSelection()
    keyCatcher.forceActiveFocus()
  }

  function setIntent(kind) {
    root.intent = kind
    keyCatcher.forceActiveFocus()
  }

  function activate(index) {
    if (index < 0 || index >= root.rows.length) return
    var key = root.rows[index].key
    if (key === "region") root.chooseRegion("image")
    else if (key === "videoregion") root.chooseRegion("video")
    else root.finish(key)
  }

  // Coordenada de la pantalla (lógica) → píxeles del PNG congelado. El PNG
  // cubre el monitor completo, el overlay su tamaño lógico con escala Qt.
  function imageCoord(value, horizontal) {
    var natural = horizontal ? frozen.implicitWidth : frozen.implicitHeight
    var total = horizontal ? panel.width : panel.height
    if (natural > 0 && total > 0) return Math.round(value * natural / total)
    return Math.round(value * Screen.devicePixelRatio)
  }

  function completeRegion() {
    var sx = panel.screen ? panel.screen.x : 0
    var sy = panel.screen ? panel.screen.y : 0
    // Clic sin arrastre: la ventana bajo el puntero. Si no hay ninguna, el
    // script reabre la barra (grabar pantalla / zona / ventana).
    if (root.selW < 4 || root.selH < 4) {
      var prefix = root.intent === "video" ? "recordwindowat:" : "windowat:"
      root.finish(prefix + Math.round(sx + root.dragX1) + "," + Math.round(sy + root.dragY1))
      return
    }
    if (root.intent === "video") {
      // gpu-screen-recorder espera la geometría lógica global del compositor.
      var vx = Math.max(0, Math.round(sx + root.selX))
      var vy = Math.max(0, Math.round(sy + root.selY))
      var vw = Math.round(root.selW)
      var vh = Math.round(root.selH)
      root.finish("videoregion:" + vx + "," + vy + "," + vw + "," + vh)
      return
    }
    var x = root.imageCoord(root.selX, true)
    var y = root.imageCoord(root.selY, false)
    var w = root.imageCoord(root.selW, true)
    var h = root.imageCoord(root.selH, false)
    root.finish("region:" + x + "," + y + "," + w + "," + h)
  }

  Process {
    id: resultProc
    onExited: root.opened = false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "capture-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // La pantalla congelada, tal como estaba antes de abrir el overlay.
    Image {
      id: frozen
      anchors.fill: parent
      source: root.imagePath
      fillMode: Image.Stretch
      asynchronous: false
      cache: false
      smooth: true
    }

    CaptureSelection {
      anchors.fill: parent
      regionMode: root.mode === "region"
      dragging: root.dragging
      selX: root.selX
      selY: root.selY
      selW: root.selW
      selH: root.selH
      pixelScale: panel.width > 0 ? frozen.implicitWidth / panel.width : Screen.devicePixelRatio
      pointerX: root.pointerX
      pointerY: root.pointerY
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: root.opened

      Keys.onEscapePressed: root.finish(null)
      Keys.onLeftPressed: if (root.mode === "menu") root.move(-1)
      Keys.onRightPressed: if (root.mode === "menu") root.move(1)
      Keys.onReturnPressed: {
        if (root.mode === "menu") root.activate(root.selectedIndex)
        else root.completeRegion()
      }
      Keys.onEnterPressed: {
        if (root.mode === "menu") root.activate(root.selectedIndex)
        else root.completeRegion()
      }
      Keys.onPressed: function(event) {
        if (root.mode === "menu" && event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
          root.activate(event.key - Qt.Key_1)
          event.accepted = true
        } else if (root.mode === "region" && event.key === Qt.Key_V) {
          root.setIntent(root.intent === "video" ? "image" : "video")
          event.accepted = true
        }
      }

      // Clic fuera de la barra: cancela. Clic derecho: cancela en cualquier modo.
      MouseArea {
        anchors.fill: parent
        visible: root.mode === "menu"
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.finish(null)
      }

      // Selección de región sobre la imagen congelada.
      MouseArea {
        anchors.fill: parent
        visible: root.mode === "region"
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        hoverEnabled: true

        onPositionChanged: function(mouse) {
          root.pointerX = mouse.x
          root.pointerY = mouse.y
          if (!root.dragging) return
          root.dragX1 = mouse.x
          root.dragY1 = mouse.y
        }
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            root.finish(null)
            return
          }
          root.dragX0 = mouse.x
          root.dragY0 = mouse.y
          root.dragX1 = mouse.x
          root.dragY1 = mouse.y
          root.pointerX = mouse.x
          root.pointerY = mouse.y
          root.dragging = true
        }
        onReleased: function(mouse) {
          if (mouse.button !== Qt.LeftButton || !root.dragging) return
          root.dragX1 = mouse.x
          root.dragY1 = mouse.y
          root.dragging = false
          root.completeRegion()
        }
      }

      CaptureRegionHint {
        visible: root.mode === "region"
        reveal: root.reveal
        intent: root.intent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        onIntentPicked: function(kind) { root.setIntent(kind) }
      }

      CaptureToolbar {
        visible: root.mode === "menu"
        reveal: root.reveal
        rows: root.rows
        currentIndex: root.selectedIndex
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        onActivated: function(index) { root.activate(index) }
        onHovered: function(index) { root.selectedIndex = index }
      }
    }
  }
}
