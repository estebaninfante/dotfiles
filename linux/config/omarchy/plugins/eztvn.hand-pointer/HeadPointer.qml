import QtQuick

// Puntero de cabeza: un anillo ámbar con un punto en el centro. Es distinto de
// las yemas (azul/rojo) y del cursor real del mouse, que no se toca.
//
// En modo scroll con la cabeza (`scrollVel` != null) se vuelve una cápsula
// vertical cian con flechas: la barra interna crece hacia arriba o hacia
// abajo según el sentido y la velocidad del desplazamiento (−1 … +1).
Item {
  id: head

  required property var tip        // [x, y] normalizado, o null
  property real screenW: 0
  property real screenH: 0
  property real size: 46
  property var scrollVel: null     // null = modo normal; número = modo scroll

  readonly property bool enScroll: scrollVel !== null && scrollVel !== undefined
  readonly property color cian: Qt.rgba(0.31, 0.76, 0.85, 0.95)

  visible: tip !== null && tip !== undefined
  width: size
  height: size

  x: (tip ? tip[0] : 0) * screenW - width / 2
  y: (tip ? tip[1] : 0) * screenH - height / 2

  // ── modo normal: anillo ámbar ──
  Rectangle {
    visible: !head.enScroll
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: Qt.rgba(1.0, 0.78, 0.25, 0.80)
  }

  Rectangle {
    visible: !head.enScroll
    anchors.centerIn: parent
    width: 8
    height: width
    radius: width / 2
    color: Qt.rgba(1.0, 0.78, 0.25, 0.95)
  }

  // ── modo scroll: cápsula con flechas y barra de velocidad ──
  Item {
    id: capsula
    visible: head.enScroll
    anchors.centerIn: parent
    width: 26
    height: 132
    readonly property real v: head.enScroll ? Math.max(-1, Math.min(1, head.scrollVel)) : 0

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.rgba(0.05, 0.12, 0.15, 0.55)
      border.width: 2
      border.color: head.cian
    }

    // Barra: desde el centro hacia el sentido del scroll.
    Rectangle {
      width: 10
      radius: 5
      x: (capsula.width - width) / 2
      height: Math.max(4, Math.abs(capsula.v) * (capsula.height / 2 - 18))
      y: capsula.v >= 0 ? capsula.height / 2 - height : capsula.height / 2
      color: head.cian
      Behavior on height { NumberAnimation { duration: 80 } }
    }

    Rectangle {  // marca del centro (zona muerta)
      width: 16; height: 2
      x: (capsula.width - width) / 2
      y: capsula.height / 2 - 1
      color: Qt.rgba(1, 1, 1, 0.6)
    }

    Text {
      text: "▲"
      color: capsula.v > 0.02 ? "white" : head.cian
      font.pixelSize: 13
      anchors.horizontalCenter: parent.horizontalCenter
      y: 3
    }
    Text {
      text: "▼"
      color: capsula.v < -0.02 ? "white" : head.cian
      font.pixelSize: 13
      anchors.horizontalCenter: parent.horizontalCenter
      y: capsula.height - height - 3
    }
  }

  Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.Linear } }
  Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.Linear } }
}
