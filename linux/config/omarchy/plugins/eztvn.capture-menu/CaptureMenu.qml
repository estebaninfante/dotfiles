import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Annotations.js" as Annotations

// PrintScreen entra directo a capturar y Shift+Print a grabar. La barra de
// abajo elige el modo: "Seleccionar área" (arrastrar zona, clic en ventana) o
// "Dibujar" (anotar con el botón izquierdo sobre la pantalla y después
// capturarla entera). La barra de arriba cambia entre captura y grabación y
// confirma. Ctrl+C copia sin guardar archivo; Esc o clic derecho cancelan.
//
// Los trazos se mandan al script y se componen sobre el PNG congelado, así que
// entran en la imagen guardada y en el portapapeles.
Item {
  id: root

  property bool opened: false
  property string selectionFile: ""
  property string doneFile: ""
  property string imagePath: ""
  property string intent: "image" // "image" | "video"
  // "area": elegir una zona con el mouse. "draw": dibujar sobre la pantalla.
  property string interaction: "area"

  property real dragX0: 0
  property real dragY0: 0
  property real dragX1: 0
  property real dragY1: 0
  property bool dragging: false
  property real pointerX: -1
  property real pointerY: -1

  // Anotaciones: la capa es dueña de los trazos; aquí sólo el pincel activo.
  property string drawTool: "pencil"
  property int drawWidth: 4
  property string drawColor: Annotations.colorHex(Color.accent)

  // 0 = recién abierto, 1 = asentado. Las barras entran con esto.
  property real reveal: 0

  readonly property bool drawMode: interaction === "draw"
  readonly property real selX: Math.min(dragX0, dragX1)
  readonly property real selY: Math.min(dragY0, dragY1)
  readonly property real selW: Math.abs(dragX1 - dragX0)
  readonly property real selH: Math.abs(dragY1 - dragY0)
  readonly property bool selectionValid: selW >= 4 && selH >= 4

  Behavior on reveal {
    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
  }

  // El plugin queda cargado entre capturas (keepLoaded), así que el estado
  // sobrevive. Se limpia lo de la captura anterior.
  function resetDrag() {
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
    root.intent = String(p.defaultAction || "image") === "record" ? "video" : "image"
    root.interaction = "area"
    root.resetDrag()
    drawing.clear()
    // El selector de color nunca queda abierto de una captura a la siguiente.
    annotations.closePicker()
    // El PNG congelado es del monitor con foco: el overlay debe vivir ahí.
    var mon = String(p.monitor || "")
    if (mon !== "") {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === mon) {
          panel.screen = screens[i]
          break
        }
      }
    }
    root.reveal = 0
    root.opened = true
    Qt.callLater(function() {
      if (!root.opened) return
      root.reveal = 1
      keys.forceActiveFocus()
    })
  }

  function close() {
    // El shell puede cerrar el panel (recarga, apagado): hay que dejar el
    // archivo de cancelación para que capture-menu suelte el lock al instante.
    root.finish(null)
  }

  function annotationPath() {
    if (root.selectionFile === "") return ""
    var cut = root.selectionFile.lastIndexOf("/")
    return (cut >= 0 ? root.selectionFile.substring(0, cut + 1) : "") + "annotations.json"
  }

  function isVideoKey(key) {
    return key !== null && key !== undefined &&
      (key === "record" || key.indexOf("videoregion:") === 0 || key.indexOf("recordwindowat:") === 0)
  }

  function outputScale() {
    if (panel.width > 0 && frozen.implicitWidth > 0)
      return frozen.implicitWidth / panel.width
    return Screen.devicePixelRatio
  }

  function finish(key) {
    var selection = root.selectionFile
    var done = root.doneFile
    var annPath = root.annotationPath()
    var ann = ""
    if (key && !root.isVideoKey(key) && annPath !== "" && root.drawMode)
      ann = drawing.serialized(root.outputScale())

    root.selectionFile = ""
    root.doneFile = ""
    if (done !== "") {
      var parts = []
      if (ann !== "")
        parts.push("printf '%s' " + Util.shellQuote(ann) + " > " + Util.shellQuote(annPath))
      if (key === null || key === undefined) {
        parts.push(": > " + Util.shellQuote(done))
      } else {
        parts.push("printf '%s\\n' " + Util.shellQuote(key) + " > " + Util.shellQuote(selection))
        parts.push(": > " + Util.shellQuote(done))
      }
      resultProc.command = ["bash", "-c", parts.join("; ")]
      resultProc.running = true
    } else {
      root.opened = false
    }
  }

  function toggleIntent() {
    if (root.intent === "video") {
      root.intent = "image"
    } else {
      // Las anotaciones no se graban: al pasar a video se descartan.
      root.intent = "video"
      root.interaction = "area"
      drawing.clear()
    }
    annotations.closePicker()
    keys.forceActiveFocus()
  }

  function setInteraction(mode) {
    if (root.intent === "video") mode = "area"
    if (mode !== "area" && mode !== "draw") return
    root.interaction = mode
    root.dragging = false
    annotations.closePicker()
    keys.forceActiveFocus()
  }

  function screenX(value) {
    return Math.max(0, Math.round((panel.screen ? panel.screen.x : 0) + value))
  }

  function screenY(value) {
    return Math.max(0, Math.round((panel.screen ? panel.screen.y : 0) + value))
  }

  function imageCoord(value, horizontal) {
    var natural = horizontal ? frozen.implicitWidth : frozen.implicitHeight
    var total = horizontal ? panel.width : panel.height
    if (natural > 0 && total > 0) return Math.round(value * natural / total)
    return Math.round(value * Screen.devicePixelRatio)
  }

  function captureWindow(x, y) {
    var prefix = root.intent === "video" ? "recordwindowat:" : "windowat:"
    root.finish(prefix + root.screenX(x) + "," + root.screenY(y))
  }

  function finishVideoRegion() {
    if (!root.selectionValid) return
    root.finish("videoregion:" + root.screenX(root.selX) + "," + root.screenY(root.selY) +
                "," + Math.round(root.selW) + "," + Math.round(root.selH))
  }

  function confirmCapture() {
    if (root.intent === "video") {
      if (root.selectionValid) root.finishVideoRegion()
      return
    }
    if (root.drawMode) {
      root.finish("full")
      return
    }
    if (!root.selectionValid) return
    root.finish("region:" + root.imageCoord(root.selX, true) + "," +
                root.imageCoord(root.selY, false) + "," +
                root.imageCoord(root.selW, true) + "," +
                root.imageCoord(root.selH, false))
  }

  // Ctrl+C: sólo portapapeles, sin archivo en Imágenes. En dibujo copia la
  // pantalla con los trazos; en área, la zona elegida (o la pantalla entera si
  // no hay zona).
  function copyToClipboard() {
    if (root.intent !== "image") return
    if (!root.drawMode && root.selectionValid) {
      root.finish("clipboardregion:" + root.imageCoord(root.selX, true) + "," +
                  root.imageCoord(root.selY, false) + "," +
                  root.imageCoord(root.selW, true) + "," +
                  root.imageCoord(root.selH, false))
    } else {
      root.finish("clipboardfull")
    }
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

    // El mismo velo en los dos modos: al pasar a dibujar se sigue viendo la
    // pantalla congelada, no la pantalla en vivo.
    CaptureSelection {
      anchors.fill: parent
      regionMode: !root.drawMode
      dragging: root.dragging
      selX: root.selX
      selY: root.selY
      selW: root.selW
      selH: root.selH
      pixelScale: panel.width > 0 ? frozen.implicitWidth / panel.width : Screen.devicePixelRatio
      pointerX: root.pointerX
      pointerY: root.pointerY
    }

    CaptureKeys {
      id: keys
      anchors.fill: parent
      active: root.opened

      onCancelled: root.finish(null)
      onConfirmed: root.confirmCapture()
      onCopyRequested: root.copyToClipboard()
      onUndoRequested: drawing.undo()
      onIntentToggled: root.toggleIntent()
      onModeRequested: function(mode) { root.setInteraction(mode) }

      CaptureCanvas {
        id: drawing
        anchors.fill: parent
        // Los trazos sólo se ven (y se guardan) en modo dibujo.
        layerVisible: root.drawMode
        tool: root.drawTool
        color: root.drawColor
        strokeWidth: root.drawWidth
      }

      CaptureMouse {
        anchors.fill: parent
        drawMode: root.drawMode
        priorSelection: root.selectionValid

        onPointerMoved: function(x, y) {
          root.pointerX = x
          root.pointerY = y
          if (drawing.drawing) drawing.extend(x, y)
        }
        onDrawingStarted: function(x, y) {
          annotations.closePicker()
          drawing.begin(x, y)
        }
        onDrawingEnded: drawing.end()
        onDragStarted: function(x, y) {
          annotations.closePicker()
          root.dragging = true
          root.dragX0 = x
          root.dragY0 = y
          root.dragX1 = x
          root.dragY1 = y
        }
        onDragMoved: function(x, y) {
          root.dragX1 = x
          root.dragY1 = y
        }
        onDragEnded: function(x, y) {
          root.dragX1 = x
          root.dragY1 = y
          root.dragging = false
          // Grabar arranca al soltar; capturar espera confirmación.
          if (root.intent === "video") root.finishVideoRegion()
        }
        onClickAt: function(x, y) {
          annotations.closePicker()
          root.captureWindow(x, y)
        }
        onCancelled: root.finish(null)
        onConfirmed: root.confirmCapture()
      }
      CaptureAnnotations {
        id: annotations
        visible: root.intent === "image"
        reveal: root.reveal
        drawMode: root.drawMode
        tool: root.drawTool
        color: root.drawColor
        strokeWidth: root.drawWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(28)
        onModePicked: function(mode) { root.setInteraction(mode) }
        onToolPicked: function(tool) { root.drawTool = tool }
        onColorPicked: function(color) { root.drawColor = color }
        onWidthCycled: root.drawWidth = root.drawWidth === 2 ? 4 : (root.drawWidth === 4 ? 8 : 2)
        onUndoRequested: drawing.undo()
        onClearRequested: drawing.clear()
      }

      CaptureToolbar {
        // Única barra de acciones; se oculta al arrastrar o dibujar.
        visible: !root.dragging && !drawing.drawing
        reveal: root.reveal
        intent: root.intent
        canConfirm: root.drawMode || root.selectionValid
        // En dibujo, confirmar ya captura la pantalla entera.
        showFull: !root.drawMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        onModeToggled: root.toggleIntent()
        onFullRequested: root.finish(root.intent === "video" ? "record" : "full")
        onConfirmed: root.confirmCapture()
      }
    }
  }
}
