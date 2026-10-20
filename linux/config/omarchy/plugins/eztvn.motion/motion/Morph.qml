import QtQuick


// Una línea de tiempo de morph con escalonado, compartida por todos los ítems
// que se transforman juntos. Es lo que hace que un cambio se sienta "de una
// pieza" y no como diez animaciones sueltas.
//
//   Morph { id: m; count: 13
//     onTick: function(t) { for (var i = 0; i < 13; i++) itemAt(i).k = m.weight(i) }
//   }
//   button.onClicked: m.go(1 - m.target)
//
// O para un morph sin escalonado (un contenedor, una página):
//
//   Morph { id: page; onTick: function(t) { page.progress = ... } }
//   // consumir `progress` directamente: ya viene suavizado y con la duración
//   // de Tokens.morph.
//
// `weight(i)` devuelve 0..1 para el ítem i de `count`, con el barrido en el
// sentido del movimiento: al abrir entra 0,1,2…; al cerrar, al revés.
QtObject {
  id: m

  // 0 = forma A, 1 = forma B. Lo que el consumidor dibuje con esto es suyo.
  property real progress: 0
  property real target: 0
  property int count: 1
  property bool running: false

  property int duration: Tokens.morph
  property int step: Tokens.staggerStepMorph
  property int fastDuration: 280
  // Al soltar un drag: asienta en la forma más cercana, sin escalonado.
  property bool dragging: false
  property bool fast: false

  // Momento en que ESTE frame va a estar en pantalla (ms). El consumidor lo
  // recibe por onTick y no tiene que recalcular relojes.
  signal tick(real t)
  signal finished()

  property real now: 0
  property real t0: -1
  property real from: 0
  property bool backward: false
  property real _ms: 1000 / 60
  property int _refreshes: 0
  property real _last: 0

  readonly property real span: Math.max(1, fast ? fastDuration : duration)

  function go(to) {
    if (m.running || m.dragging) return
    if (Math.abs(to - m.progress) < 0.001) return
    m.from = m.progress
    m.target = to
    m.backward = to < m.progress
    m.fast = false
    m.t0 = -1
    m._last = 0
    m.running = true
  }

  // Drag continuo: el dedo manda, sin escalonado ni easing.
  function beginDrag() { m.running = false; m.dragging = true }
  function dragTo(v) { m.progress = Tokens.reduced ? (v > 0.5 ? 1 : 0) : Math.max(0, Math.min(1, v)) }
  function cancelDrag() { m.dragging = false }
  function endDrag() {
    if (!m.dragging) return
    m.dragging = false
    var snap = m.progress > 0.5 ? 1 : 0
    m.from = m.progress
    m.target = snap
    m.backward = snap < m.progress
    m.fast = true
    m.t0 = -1
    m._last = 0
    m.running = true
  }

  // Peso del ítem i (0..count-1) en el frame actual.
  function weight(i) {
    if (Tokens.reduced) return m.target
    if (!m.running && !m.dragging) return m.progress
    if (m.dragging) return m.progress
    if (m.t0 < 0) return m.from
    var ord = m.backward ? m.count - 1 - i : i
    // Asentar un drag no se escalona: todo llega junto.
    var d = m.fast ? 0 : ord * m.step
    var k = (m.now - m.t0 - d) / m.span
    var e = Tokens.curveOf("draw")
    // Misma curva que el resto: in-out cúbica, no hace falta leer tokens.
    var x = Math.max(0, Math.min(1, k))
    return m.from + (m.target - m.from) * (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2)
  }

  readonly property FrameAnimation anim: FrameAnimation {
    running: m.running
    onTriggered: {
      var ms = frameTime * 1000
      if (!(ms > 0 && ms < 100)) ms = 1000 / 60
      m._ms = ms
      m._refreshes++
      // Un refresco de cada dos en pantallas de más de 96 Hz: pintar a 144 fps
      // con frames parejos obliga a que algunos caigan entre refrescos.
      if (ms < 10.5 && m._refreshes % 2) return
      // El reloj nunca retrocede (un frame largo seguido de uno corto temblaba).
      var t = Math.max(Date.now() + ms, m._last)
      if (m.t0 < 0) m.t0 = t
      m._last = t
      m.now = t
      var k = Math.min(1, (t - m.t0) / m.span)
      m.progress = m.from + (m.target - m.from) * (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2)
      m.tick(t)
      if (k >= 1) {
        m.progress = m.target
        m.running = false
        m.finished()
      }
    }
  }
}
