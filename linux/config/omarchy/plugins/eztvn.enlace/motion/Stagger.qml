import QtQuick

// El barrido de un grupo, sin que el consumidor lleve la cuenta.
//
//   Stagger { id: rows; count: 12; shown: panel.opened }
//   Repeater {
//     model: 12
//     delegate: Reveal {
//       shown: rows.shown
//       delay: rows.delay(index)
//       duration: rows.duration
//       Fila { }
//     }
//   }
//
// Al abrir entra 0,1,2…; `reverse()` invierte el próximo barrido (al volver, el
// orden sigue al gesto en vez de deshacerlo). El delay está topado: un grupo de
// 40 no tarda 40 pasos.
QtObject {
  id: s

  property int count: 1
  property bool shown: true
  // Dirección del próximo barrido. `reverse()` la cambia; también se puede
  // fijar desde el consumidor (p. ej. según la tecla que abrió el panel).
  property bool backward: false
  property int step: Tokens.staggerStep
  property int duration: Tokens.base
  property int maxStep: Tokens.staggerMax
  // Invertir solo, cada vez que el grupo se vuelve a abrir.
  property bool autoReverse: true

  // Posición de barrido del ítem i (0 = primero en entrar).
  function position(i) {
    return backward ? count - 1 - i : i
  }

  function delay(i) {
    if (Tokens.reduced) return 0
    return Math.min(position(i), maxStep) * step
  }

  function open() {
    if (autoReverse) backward = !backward
    shown = true
  }
  function close() { shown = false }
  function toggle() { if (shown) close(); else open() }
  function reverse() { backward = !backward }
}
