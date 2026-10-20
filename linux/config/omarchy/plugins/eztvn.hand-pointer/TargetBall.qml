import QtQuick

// Diana del entrenamiento pasivo: la bola a la que hay que mirar.
// La posición llega normalizada (0..1) en el campo `target` del socket de
// vision-hub. Cuando el entrenamiento está en pausa (tecleás, movés el mouse o
// dictás) el campo viene en null y la bola desaparece.
Item {
  id: target

  required property var tip        // [x, y] normalizado, o null
  property real screenW: 0
  property real screenH: 0
  property real size: 34

  visible: tip !== null && tip !== undefined
  width: size
  height: size

  x: (tip ? tip[0] : 0) * screenW - width / 2
  y: (tip ? tip[1] : 0) * screenH - height / 2

  // Halo suave para que se vea sobre cualquier fondo.
  Rectangle {
    anchors.centerIn: parent
    width: parent.width + 10
    height: width
    radius: width / 2
    color: Qt.rgba(0.20, 0.85, 1.0, 0.10)
  }

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: Qt.rgba(0.20, 0.85, 1.0, 0.85)
  }

  Rectangle {
    anchors.centerIn: parent
    width: 12
    height: width
    radius: width / 2
    color: Qt.rgba(1, 1, 1, 0.95)
  }

  Behavior on x { NumberAnimation { duration: 80; easing.type: Easing.Linear } }
  Behavior on y { NumberAnimation { duration: 80; easing.type: Easing.Linear } }
}
