import QtQuick

// Mouse del overlay. No decide: avisa qué pasó y CaptureMenu mueve el estado.
// Izquierda arrastra (zona o trazo según el modo) o hace clic; derecha cancela.
MouseArea {
  id: root

  property bool drawMode: false
  property bool priorSelection: false
  property real pressX: 0
  property real pressY: 0
  property bool pressing: false
  property bool dragging: false

  signal pointerMoved(real x, real y)
  signal drawingStarted(real x, real y)
  signal drawingEnded()
  signal dragStarted(real x, real y)
  signal dragMoved(real x, real y)
  signal dragEnded(real x, real y)
  signal clickAt(real x, real y)
  signal cancelled()
  signal confirmed()

  acceptedButtons: Qt.LeftButton | Qt.RightButton
  cursorShape: Qt.CrossCursor
  hoverEnabled: true

  onPositionChanged: function(mouse) {
    root.pointerMoved(mouse.x, mouse.y)
    if (root.drawMode || !root.pressing) return
    if (!root.dragging &&
        (Math.abs(mouse.x - root.pressX) > 3 || Math.abs(mouse.y - root.pressY) > 3)) {
      root.dragging = true
      root.dragStarted(root.pressX, root.pressY)
    }
    if (root.dragging) root.dragMoved(mouse.x, mouse.y)
  }

  onPressed: function(mouse) {
    if (mouse.button === Qt.RightButton) {
      root.cancelled()
      return
    }
    if (root.drawMode) {
      root.drawingStarted(mouse.x, mouse.y)
      return
    }
    root.pressX = mouse.x
    root.pressY = mouse.y
    root.pressing = true
    root.dragging = false
  }

  onReleased: function(mouse) {
    if (mouse.button === Qt.RightButton) return
    if (root.drawMode) {
      root.drawingEnded()
      return
    }
    if (!root.pressing) return
    root.pressing = false
    if (root.dragging) {
      root.dragging = false
      root.dragEnded(mouse.x, mouse.y)
    } else if (!root.priorSelection) {
      root.clickAt(mouse.x, mouse.y)
    }
  }

  onDoubleClicked: function(mouse) {
    if (!root.drawMode) root.confirmed()
  }
}
