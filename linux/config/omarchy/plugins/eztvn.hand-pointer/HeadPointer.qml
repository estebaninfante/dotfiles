import QtQuick

// Puntero de cabeza: un anillo ámbar con un punto en el centro. Es distinto de
// las yemas (azul/rojo) y del cursor real del mouse, que no se toca.
Item {
  id: head

  required property var tip        // [x, y] normalizado, o null
  property real screenW: 0
  property real screenH: 0
  property real size: 46

  visible: tip !== null && tip !== undefined
  width: size
  height: size

  x: (tip ? tip[0] : 0) * screenW - width / 2
  y: (tip ? tip[1] : 0) * screenH - height / 2

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: Qt.rgba(1.0, 0.78, 0.25, 0.80)
  }

  Rectangle {
    anchors.centerIn: parent
    width: 8
    height: width
    radius: width / 2
    color: Qt.rgba(1.0, 0.78, 0.25, 0.95)
  }

  Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.Linear } }
  Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.Linear } }
}
