import QtQuick

// Una yema: círculo azul para la mano izquierda, rojo para la derecha.
// La posición llega normalizada (0..1) desde vision-hub; acá se escala a la
// pantalla y se interpola un instante para que el movimiento no se vea a saltos.
Rectangle {
  id: dot

  required property var tip        // [x, y] normalizado, o null
  required property string side    // "Left" | "Right"
  property bool dim: false         // pose bloqueada (mano sobre la cara)
  property real screenW: 0
  property real screenH: 0
  property real dotSize: 30

  readonly property bool right: side === "Right"

  visible: tip !== null && tip !== undefined
  width: dotSize
  height: dotSize
  radius: width / 2
  antialiasing: true

  color: right
    ? Qt.rgba(0.95, 0.30, 0.30, dim ? 0.20 : 0.45)
    : Qt.rgba(0.29, 0.56, 0.95, dim ? 0.20 : 0.45)
  border.width: 1
  border.color: right
    ? Qt.rgba(1.0, 0.62, 0.62, dim ? 0.25 : 0.55)
    : Qt.rgba(0.60, 0.78, 1.0, dim ? 0.25 : 0.55)

  x: (tip ? tip[0] : 0) * screenW - width / 2
  y: (tip ? tip[1] : 0) * screenH - height / 2

  // 70 ms lineales: cubren el hueco entre muestras (~50-60 ms) sin retraso
  // perceptible.
  Behavior on x { NumberAnimation { duration: 70; easing.type: Easing.Linear } }
  Behavior on y { NumberAnimation { duration: 70; easing.type: Easing.Linear } }
}
