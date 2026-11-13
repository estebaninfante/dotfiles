import QtQuick

// Foco y teclado del overlay, nada más: Esc o clic derecho cancelan, Enter
// confirma, Ctrl+C copia sin guardar, Ctrl+Z deshace el último trazo, Tab
// alterna captura/grabación y 1/2 eligen área o dibujo. Los hijos (lienzo,
// mouse, barras) los declara CaptureMenu.
Item {
  id: root

  property bool active: false

  signal cancelled()
  signal confirmed()
  signal copyRequested()
  signal undoRequested()
  signal intentToggled()
  signal modeRequested(string mode)

  focus: active

  Keys.onEscapePressed: root.cancelled()
  Keys.onReturnPressed: root.confirmed()
  Keys.onEnterPressed: root.confirmed()

  Keys.onPressed: function(event) {
    if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Z) {
      root.undoRequested()
      event.accepted = true
    } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_C) {
      root.copyRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab) {
      root.intentToggled()
      event.accepted = true
    } else if (event.key === Qt.Key_1) {
      root.modeRequested("area")
      event.accepted = true
    } else if (event.key === Qt.Key_2) {
      root.modeRequested("draw")
      event.accepted = true
    }
  }
}
