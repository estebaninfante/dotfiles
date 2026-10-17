import QtQuick
import QtQuick.Shapes
import qs.Commons

// Anillo HUD del menú radial.
//
//   punteado: false  → arco corto (el foco de la opción elegida), sin animar.
//   punteado: true   → círculo punteado que puede girar lento para dar vida.
//
// El arco se dibuja centrado arriba; quien lo usa lo rota al ángulo elegido.
Item {
  id: aro

  property real radio: 100
  property color color
  property real grosor: 1
  property real apertura: 40
  property bool punteado: false

  width: radio * 2
  height: width

  Shape {
    anchors.fill: parent

    ShapePath {
      fillColor: "transparent"
      strokeColor: aro.color
      strokeWidth: aro.grosor
      capStyle: ShapePath.RoundCap
      strokeStyle: aro.punteado ? ShapePath.DashLine : ShapePath.SolidLine
      dashPattern: aro.punteado ? [1, 8] : []

      PathAngleArc {
        centerX: aro.radio
        centerY: aro.radio
        radiusX: aro.radio - aro.grosor / 2
        radiusY: aro.radio - aro.grosor / 2
        startAngle: aro.punteado ? 0 : -90 - aro.apertura / 2
        sweepAngle: aro.punteado ? 360 : aro.apertura
      }
    }
  }
}
