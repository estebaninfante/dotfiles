import QtQuick


// Aparición y desaparición pareadas. Todo lo que entra o sale de la pantalla
// pasa por acá: nunca `visible: false` de golpe, nunca un pop sin transición.
//
//   Reveal { shown: panel.opened; delay: Tokens.delayFor(i)
//     Card { anchors.fill: parent }
//   }
//
// Entra desde abajo y un poco chico (rise / fromScale de motion.json); sale
// hacia el mismo lugar, más rápido. Se queda montado: el consumidor decide si
// el contenido debe seguir vivo (scroll, foco) o no.
Item {
  id: r

  default property alias content: holder.data

  property bool shown: true
  // Retraso de entrada (sale sin retraso, para no alargar el cierre).
  property int delay: 0
  // Override puntual; -1 = usar Tokens.base (entrar) / Tokens.fast (salir).
  property int duration: -1
  readonly property real k: kk
  readonly property bool entered: kk >= 1
  readonly property bool gone: kk <= 0.001
  property real rise: Tokens.revealRise
  property real fromScale: Tokens.revealFrom
  // Para contenido que tiene que seguir existiendo aunque no se vea.
  property bool keepMounted: true

  property real kk: shown ? 1 : 0

  implicitWidth: 0
  implicitHeight: 0
  visible: kk > 0.001 || shown
  enabled: shown
  opacity: kk
  scale: fromScale + (1 - fromScale) * kk
  transformOrigin: Item.Center
  transform: Translate { y: (1 - r.kk) * r.rise }

  Item {
    id: holder
    anchors.fill: parent
  }

  SequentialAnimation {
    id: anim
    PauseAnimation { duration: r.shown ? r.delay : 0 }
    NumberAnimation {
      target: r
      property: "kk"
      to: r.shown ? 1 : 0
      duration: r.duration >= 0 ? r.duration : (r.shown ? Tokens.base : Tokens.fast)
      easing.type: r.shown ? Tokens.enter : Tokens.exit
    }
  }

  onShownChanged: {
    anim.stop()
    anim.start()
  }
}
