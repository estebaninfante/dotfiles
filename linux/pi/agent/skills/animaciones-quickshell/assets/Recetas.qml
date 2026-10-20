// Recetas del motor de movimiento, listas para copiar. Este archivo carga
// (verificado con qs offscreen) y cada componente es autónomo.
//
// Requiere el motor al lado: `motion/` (a copiarlo con scripts/motion-vendor.sh).
// Se instancia el root solo para probar que todo compila.
import QtQuick
import qs.Commons
import "motion"

Item {
  id: root
  width: 640
  height: 400

  // 1 — Aparece / desaparece ------------------------------------------------
  // Nunca `visible: false` a mano. `shown` es el único dato que le pasás.
  component Aparecer: Reveal {
    id: card
    property string etiqueta: ""
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Color.menu.selectedBackground
      Text {
        anchors.centerIn: parent
        text: card.etiqueta
        color: Color.menu.text
      }
    }
  }

  // 2 — Lista en barrido ----------------------------------------------------
  // Stagger lleva la cuenta, la dirección y el tope. No calcules delays.
  component Lista: Item {
    id: list
    property int filas: 8
    property bool abierta: true
    implicitHeight: column.implicitHeight

    Stagger { id: rows; count: list.filas; shown: list.abierta }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(4)
      Repeater {
        model: list.filas
        delegate: Reveal {
          required property int index
          width: column.width
          height: Style.space(24)
          shown: rows.shown
          delay: rows.delay(index)
          duration: rows.duration
          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Color.menu.selectedBackground
          }
        }
      }
    }
  }

  // 3 — Morph ---------------------------------------------------------------
  // Una sola línea de tiempo: `weight(i)` es todo lo que el dibujo necesita.
  // Acá una fila de puntos se abre en círculo; el consumidor real decide qué
  // hacer con el peso (x/y, tamaño, opacidad, proyección de un canvas).
  component Forma: Item {
    id: shape
    property real k: 0              // 0 = fila, 1 = círculo

    Morph {
      id: morph
      count: shape.dots
      onTick: function(now) {
        for (var i = 0; i < shape.dots; i++) dots.itemAt(i).k = morph.weight(i)
      }
    }
    property int dots: 24

    Repeater {
      id: dots
      model: shape.dots
      delegate: Rectangle {
        required property int index
        property real k: 0
        readonly property real angle: index / shape.dots * Math.PI * 2
        width: 5; height: 5; radius: 2.5
        x: (1 - k) * (index / shape.dots) * shape.width + k * (shape.width / 2 + Math.cos(angle) * shape.height * 0.4) - 2.5
        y: (1 - k) * (shape.height / 2) + k * (shape.height / 2 + Math.sin(angle) * shape.height * 0.4) - 2.5
        color: Color.accent
      }
    }
    MouseArea { anchors.fill: parent; onClicked: morph.go(morph.progress > 0.5 ? 0 : 1) }
  }

  // 4 — Resorte -------------------------------------------------------------
  // Vuelve sola a su lugar, con la física del sistema (tokens, no números).
  component Resorte: Item {
    id: springy
    implicitHeight: Style.space(40)

    Rectangle {
      id: pill
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40); height: width; radius: width / 2
      x: 0
      color: Color.accent

      SpringAnimation on x {
        id: spring
        spring: Tokens.springStiffness
        damping: Tokens.springDamping
        mass: Tokens.springMass
        epsilon: Tokens.springEpsilon
        to: 0
      }
      MouseArea {
        anchors.fill: parent
        drag.target: pill
        drag.axis: Drag.XAxis
        drag.minimumX: 0
        drag.maximumX: springy.width - pill.width
        onPressed: spring.stop()
        onReleased: { spring.stop(); spring.start() }
      }
    }
  }

  // Prueba de carga: las cuatro recetas instanciadas una vez.
  Aparecer { x: 0; y: 0; width: 120; height: 48; etiqueta: "aparece" }
  Lista { x: 140; y: 0; width: 160 }
  Forma { x: 0; y: 70; width: 200; height: 140 }
  Resorte { x: 220; y: 70; width: 200 }
}
