import QtQuick

// Una línea de tiempo de morph con escalonado, compartida por todos los ítems
// que se transforman juntos. Es lo que hace que un cambio se sienta "de una
// pieza" y no como diez animaciones sueltas.
//
//   Morph { id: m; count: 13
//     onTick: function(now) { for (var i = 0; i < 13; i++) itemAt(i).k = m.weight(i) }
//   }
//   onClicked: m.go(1 - m.progress)
//
// `weight(i)` devuelve 0..1 para el ítem i de `count`, con el barrido en el
// sentido del movimiento: al abrir entra 0,1,2…; al cerrar, al revés.
//
// `advance(ms)` es la línea de tiempo pura: no sabe de frames. El FrameAnimation
// de abajo la alimenta con el tiempo real de cada frame; los tests la llaman a
// mano y obtienen el mismo resultado, sin depender del render.
QtObject {
  id: m

  // 0 = forma A, 1 = forma B. Lo que el consumidor dibuje con esto es suyo.
  property real progress: 0
  property real target: 0
  property int count: 1
  property bool running: false

  property int duration: 260
  property int step: 40
  property int fastDuration: 280
  property bool dragging: false
  property bool fast: false

  signal tick(real now)
  signal finished()

  // Tiempo acumulado desde el comienzo del morph (ms). Determinista: sólo
  // cambia por advance().
  property real now: 0
  property real t0: -1
  property real from: 0
  property bool backward: false
  property real _pending: 0
  property int _refreshes: 0

  readonly property real span: Math.max(1, fast ? fastDuration : duration)

  function go(to) {
    if (m.running || m.dragging) return
    if (Math.abs(to - m.progress) < 0.001) return
    // Sin animaciones: el cambio es instantáneo y avisa igual, para que el
    // consumidor refresque lo que dependa de `progress`.
    if (m.calm) {
      m.progress = to
      m.target = to
      m.t0 = -1
      m.tick(m.now)
      m.finished()
      return
    }
    m.from = m.progress
    m.target = to
    m.backward = to < m.progress
    m.fast = false
    m.t0 = -1
    m.now = 0
    m._pending = 0
    m.running = true
  }

  // Drag continuo: el dedo manda, sin escalonado ni easing.
  function beginDrag() { m.running = false; m.dragging = true }
  function dragTo(v) { m.progress = m.calm ? (v > 0.5 ? 1 : 0) : Math.max(0, Math.min(1, v)) }
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
    m.now = 0
    m._pending = 0
    m.running = true
  }

  // Se puede apagar el motion sin tocar los consumidores. Si se apaga a mitad
  // de un morph, asienta en el destino en el acto (no deja nada a medias).
  property bool calm: false
  onCalmChanged: {
    if (!m.calm || !m.running) return
    m.progress = m.target
    m.running = false
    m.tick(m.now)
    m.finished()
  }

  // Peso del ítem i (0..count-1) en el instante actual.
  function weight(i) {
    if (!m.running || m.dragging || m.calm) return m.progress
    if (m.t0 < 0) return m.from
    var ord = m.backward ? m.count - 1 - i : i
    var d = m.fast ? 0 : ord * m.step
    var k = Math.max(0, Math.min(1, (m.now - m.t0 - d) / m.span))
    var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2
    return m.from + (m.target - m.from) * e
  }

  // Un paso de línea de tiempo. Sin frames, sin Date.now: mismo resultado
  // siempre. Devuelve el progreso global.
  function advance(ms) {
    if (!m.running) return m.progress
    // Un stall largo (suspensión, carga) avanza como mucho 100 ms: al volver,
    // la animación asienta en vez de reproducirse en cámara lenta.
    var dt = ms > 0 ? Math.min(ms, 100) : 1000 / 60
    m.now += dt
    if (m.t0 < 0) m.t0 = m.now
    var k = Math.min(1, (m.now - m.t0) / m.span)
    var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2
    m.progress = m.from + (m.target - m.from) * e
    m.tick(m.now)
    if (k >= 1) {
      m.progress = m.target
      m.running = false
      m.finished()
    }
    return m.progress
  }

  property FrameAnimation anim: FrameAnimation {
    running: m.running
    onTriggered: {
      var ms = frameTime * 1000
      if (!(ms > 0 && ms < 100)) ms = 1000 / 60
      m._pending += ms
      m._refreshes++
      // En pantallas de más de 96 Hz se descarta un refresco de cada dos: pintar
      // a 144 fps con frames parejos deja algunos entre refrescos (stutter).
      if (ms < 10.5 && m._refreshes % 2) return
      var dt = m._pending
      m._pending = 0
      m.advance(dt)
    }
  }
}
