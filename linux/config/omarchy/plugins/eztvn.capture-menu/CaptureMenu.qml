import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Annotations.js" as Annotations

// PrintScreen entra directo a capturar y Shift+Print a grabar: arrastrar toma
// la zona, un clic toma la ventana bajo el puntero. En captura se puede dibujar
// con el botón derecho (lápiz, línea, recuadro, flecha) antes de confirmar.
// La barra superior cambia el modo; la inferior elige la anotación.
// Ctrl+C copia la zona al portapapeles sin guardar archivo (capturas de un
// solo uso); sin zona elegida copia la pantalla entera, también sin guardar.
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
  property int selectedIndex: 0

  property real dragX0: 0
  property real dragY0: 0
  property real dragX1: 0
  property real dragY1: 0
  property bool dragging: false
  property bool pressing: false
  property real pressX: 0
  property real pressY: 0
  property bool priorSelection: false
  property real pointerX: -1
  property real pointerY: -1

  // Anotaciones: la capa es dueña de los trazos; aquí sólo el pincel activo.
  property string drawTool: "pencil"
  property int drawWidth: 4
  property string drawColor: Annotations.colorHex(Color.accent)

  // 0 = recién abierto, 1 = asentado. Las barras entran con esto.
  property real reveal: 0

  readonly property real selX: Math.min(dragX0, dragX1)
  readonly property real selY: Math.min(dragY0, dragY1)
  readonly property real selW: Math.abs(dragX1 - dragX0)
  readonly property real selH: Math.abs(dragY1 - dragY0)
  readonly property bool selectionValid: selW >= 4 && selH >= 4
  readonly property var palette: [
    Annotations.colorHex(Color.accent),
    Annotations.colorHex(Color.urgent),
    Annotations.colorHex(Color.foreground)
  ]

  readonly property var rows: [
    { key: "region", icon: "󰹵", label: "Zona" },
    { key: "full",   icon: "󰹞", label: "Pantalla" }
  ]

  Behavior on reveal {
    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
  }

  // El plugin queda cargado entre capturas (keepLoaded), así que el estado
  // sobrevive. Se limpia todo lo de la captura anterior.
  function resetSelection() {
    root.dragX0 = 0
    root.dragY0 = 0
    root.dragX1 = 0
    root.dragY1 = 0
    root.dragging = false
    root.pressing = false
    root.priorSelection = false
    root.pointerX = -1
    root.pointerY = -1
    drawing.clear()
  }

  function open(payloadJson) {
    var p = ({})
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { p = ({}) }
    root.selectionFile = String(p.selectionFile || "")
    root.doneFile = String(p.doneFile || "")
    root.imagePath = String(p.imagePath || "")
    root.intent = String(p.defaultAction || "image") === "record" ? "video" : "image"
    root.selectedIndex = 0
    root.resetSelection()
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
      keyCatcher.forceActiveFocus()
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
    if (key && !root.isVideoKey(key) && annPath !== "")
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

  function toggleMode() {
    if (root.intent === "video") {
      root.intent = "image"
    } else {
      // Las anotaciones no se graban: al pasar a video se descartan.
      root.intent = "video"
      drawing.clear()
    }
    keyCatcher.forceActiveFocus()
  }

  function chooseRegion() {
    root.resetSelection()
    keyCatcher.forceActiveFocus()
  }

  function activate(index) {
    if (index < 0 || index >= root.rows.length) return
    var key = root.rows[index].key
    if (key === "region") root.chooseRegion()
    else if (key === "full") root.finish(root.intent === "video" ? "record" : "full")
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
    if (!root.selectionValid) return
    if (root.intent === "video") {
      root.finishVideoRegion()
      return
    }
    root.finish("region:" + root.imageCoord(root.selX, true) + "," +
                root.imageCoord(root.selY, false) + "," +
                root.imageCoord(root.selW, true) + "," +
                root.imageCoord(root.selH, false))
  }

  // Ctrl+C: sólo portapapeles, sin archivo en Imágenes. Si no hay zona
  // elegida copia la pantalla entera (también sin guardar).
  function copyToClipboard() {
    if (root.intent !== "image") return
    if (root.selectionValid) {
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

    CaptureSelection {
      anchors.fill: parent
      regionMode: true
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

      CaptureCanvas {
        id: drawing
        anchors.fill: parent
        layerVisible: root.intent === "image"
        tool: root.drawTool
        color: root.drawColor
        strokeWidth: root.drawWidth
        onCancelled: root.finish(null)
      }

      Keys.onEscapePressed: root.finish(null)
      Keys.onReturnPressed: root.confirmCapture()
      Keys.onEnterPressed: root.confirmCapture()
      Keys.onPressed: function(event) {
        console.log("capture-key key=" + event.key + " mods=" + event.modifiers + " text=" + event.text)
        if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Z) {
          drawing.undo()
          event.accepted = true
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_C) {
          root.copyToClipboard()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          root.toggleMode()
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_2) {
          root.activate(event.key - Qt.Key_1)
          event.accepted = true
        }
      }

      // Izquierda: zona o clic en ventana. Derecha: dibujar en captura.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        hoverEnabled: true

        onPositionChanged: function(mouse) {
          root.pointerX = mouse.x
          root.pointerY = mouse.y

          if (drawing.drawing) {
            drawing.extend(mouse.x, mouse.y)
            return
          }
          if (!root.pressing) return
          if (!root.dragging &&
              (Math.abs(mouse.x - root.pressX) > 3 || Math.abs(mouse.y - root.pressY) > 3)) {
            root.dragging = true
            root.dragX0 = root.pressX
            root.dragY0 = root.pressY
          }
          if (root.dragging) {
            root.dragX1 = mouse.x
            root.dragY1 = mouse.y
          }
        }
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            if (root.intent !== "image") {
              root.finish(null)
              return
            }
            drawing.begin(mouse.x, mouse.y)
            return
          }
          root.pressX = mouse.x
          root.pressY = mouse.y
          root.priorSelection = root.selectionValid
          root.pressing = true
          root.dragging = false
        }
        onReleased: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            drawing.end()
            return
          }
          if (!root.pressing) return
          root.pressing = false
          if (root.dragging) {
            root.dragX1 = mouse.x
            root.dragY1 = mouse.y
            root.dragging = false
            // Grabar arranca al soltar; capturar espera anotaciones/confirmación.
            if (root.intent === "video") root.finishVideoRegion()
          } else if (!root.priorSelection) {
            root.captureWindow(mouse.x, mouse.y)
          }
        }
        onDoubleClicked: root.confirmCapture()
      }

      CaptureAnnotations {
        visible: root.intent === "image"
        reveal: root.reveal
        tool: root.drawTool
        color: root.drawColor
        strokeWidth: root.drawWidth
        palette: root.palette
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(28)
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
        rows: root.rows
        intent: root.intent
        currentIndex: root.selectedIndex
        canConfirm: root.selectionValid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        onActivated: function(index) { root.activate(index) }
        onHovered: function(index) { root.selectedIndex = index }
        onModeToggled: root.toggleMode()
        onConfirmed: root.confirmCapture()
      }
    }
  }
}
