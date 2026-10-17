import QtQuick
import qs.Commons

// Una opción del menú radial: placa de vidrio, icono y etiqueta, con halo,
// onda y transiciones cuando queda elegida. Todo el movimiento vive acá; el
// layout (posición y ángulo) lo decide Outline.qml.
Item {
  id: nodo

  required property var item
  property bool elegida: false
  property bool atenuada: false
  property bool hijo: false
  property real lado: 120
  property real fuenteIcono: 40
  property real fuenteTexto: 18
  property string familia: ""
  property color acento
  property color tinta
  property color fondo

  // La placa crece con la etiqueta: los nombres largos no se cortan ni se
  // salen del fondo.
  readonly property real ancho: Math.max(lado, etiqueta.implicitWidth + lado * 0.34)

  width: ancho
  height: lado
  opacity: atenuada ? 0.38 : 1
  scale: elegida ? 1.06 : 1

  Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
  Behavior on scale { SpringAnimation { spring: 5; damping: 0.5; mass: 1 } }

  // Halo: la luz que sale de la placa elegida.
  Rectangle {
    anchors.fill: placa
    anchors.margins: -nodo.lado * 0.17
    radius: height / 2
    color: Util.alpha(nodo.acento, 0.14)
    opacity: nodo.elegida ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
  }

  // Sombra corrida: da profundidad a la placa.
  Rectangle {
    anchors.fill: placa
    anchors.topMargin: nodo.lado * 0.05
    radius: placa.radius
    color: Util.alpha(nodo.fondo, 0.5)
  }

  Rectangle {
    id: placa
    anchors.fill: parent
    radius: nodo.lado * 0.30
    color: Util.alpha(Qt.lighter(nodo.fondo, nodo.elegida ? 2.4 : 1.6), 0.93)
    border.width: nodo.elegida ? 1.6 : 1
    border.color: nodo.elegida ? nodo.acento : Util.alpha(nodo.tinta, 0.10)

    Behavior on color { ColorAnimation { duration: 170 } }
    Behavior on border.color { ColorAnimation { duration: 170 } }

    // Brillo de vidrio: la luz que pega arriba.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(nodo.tinta, nodo.elegida ? 0.12 : 0.06) }
        GradientStop { position: 0.62; color: Util.alpha(nodo.tinta, 0.0) }
      }
    }

    // Subrayado de selección.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: nodo.lado * 0.055
      width: parent.width * (nodo.elegida ? 0.44 : 0)
      height: 2
      radius: 1
      color: nodo.acento
      Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: nodo.lado * 0.012

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: nodo.item.icono || ""
      color: nodo.elegida ? nodo.acento : Util.alpha(nodo.tinta, 0.95)
      font.family: nodo.familia
      font.pixelSize: nodo.fuenteIcono
      Behavior on color { ColorAnimation { duration: 170 } }
    }

    Text {
      id: etiqueta
      anchors.horizontalCenter: parent.horizontalCenter
      text: (nodo.item.texto || "").toUpperCase()
      color: nodo.elegida ? nodo.acento : Util.alpha(nodo.tinta, 0.78)
      font.family: nodo.familia
      font.pixelSize: nodo.fuenteTexto
      font.letterSpacing: nodo.fuenteTexto * 0.07
      Behavior on color { ColorAnimation { duration: 170 } }
    }
  }

  // Onda de selección: un anillo que se abre y se apaga al elegir.
  Rectangle {
    id: onda
    anchors.fill: placa
    radius: placa.radius
    color: "transparent"
    border.width: 1.5
    border.color: nodo.acento
    visible: nodo.elegida
    opacity: 0

    NumberAnimation { id: ondaCrece; target: onda; property: "scale"; from: 1; to: 1.42; duration: 340; easing.type: Easing.OutCubic }
    NumberAnimation { id: ondaFade; target: onda; property: "opacity"; from: 0.5; to: 0; duration: 340; easing.type: Easing.OutCubic }

    onVisibleChanged: {
      if (!nodo.elegida) return
      onda.scale = 1
      ondaCrece.restart()
      ondaFade.restart()
    }
  }
}
