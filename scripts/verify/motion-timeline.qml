// Test determinista de la línea de tiempo del motor de movimiento.
// No usa render: llama Morph.advance() a mano. verify/motion.sh lo corre en
// un Quickshell offscreen y exige MOTION_TEST_OK.
import QtQuick
import Quickshell
import "file:@ENGINE@"

ShellRoot {
  id: root
  property int fails: 0
  function ok(cond, name) {
    if (!cond) { fails++; console.log("FAIL " + name) }
  }

  Morph {
    id: m
    count: 4
    duration: 260
    step: 40

    Component.onCompleted: {
      // Ida: escalonado en el sentido del movimiento.
      m.go(1)
      if (!m.running) root.ok(false, "arranca")
      for (var i = 0; i < 10; i++) m.advance(16)
      root.ok(m.weight(0) > m.weight(3), "escalonado hacia adelante")
      for (var j = 0; j < 40; j++) m.advance(16)
      root.ok(!m.running && m.progress === 1, "termina en la forma B")
      root.ok(m.weight(0) === 1 && m.weight(3) === 1, "todos los pesos en 1")

      // Vuelta: el barrido se invierte, no vuelve sobre sus pasos.
      m.go(0)
      for (var k = 0; k < 6; k++) m.advance(16)
      root.ok(m.weight(3) < m.weight(0), "barrido inverso")
      for (var z = 0; z < 40; z++) m.advance(16)

      // Sin animaciones: instantáneo y avisando.
      m.calm = true
      m.go(1)
      root.ok(m.progress === 1 && !m.running, "calm: instantáneo")

      // Un stall largo asienta, no reproduce en cámara lenta.
      m.calm = false
      m.go(0)
      for (var q = 0; q < 4; q++) m.advance(2000)
      root.ok(m.progress === 0 && !m.running, "stall largo asienta")

      // Drag: el dedo manda; al soltar asienta en la forma más cercana.
      m.beginDrag(); m.dragTo(0.7)
      root.ok(m.progress === 0.7, "drag continuo")
      m.endDrag()
      root.ok(m.running && m.fast, "suelta y asienta")
      for (var w = 0; w < 30; w++) m.advance(16)
      root.ok(m.progress === 1 && !m.running, "asienta en la más cercana")

      console.log(root.fails === 0 ? "MOTION_TEST_OK" : "MOTION_TEST_FAIL " + root.fails)
      Qt.quit()
    }
  }
}
