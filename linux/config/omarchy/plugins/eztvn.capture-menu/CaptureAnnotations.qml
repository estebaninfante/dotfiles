import QtQuick
import QtQuick.Layouts
import qs.Commons

// Paleta de anotación: herramienta, color, grosor, deshacer y borrar.
// Se dibuja con el botón derecho sobre la pantalla; esta barra sólo elige cómo.
Item {
  id: root

  property string tool: "pencil"
  property string color: "#ffffff"
  property int strokeWidth: 4
  property var palette: []
  property real reveal: 0

  signal toolPicked(string tool)
  signal colorPicked(string color)
  signal widthCycled()
  signal undoRequested()
  signal clearRequested()

  readonly property var tools: [
    { key: "pencil", label: "Lápiz" },
    { key: "line", label: "Línea" },
    { key: "rect", label: "Recuadro" },
    { key: "arrow", label: "Flecha" }
  ]

  implicitWidth: card.width
  implicitHeight: card.height

  Rectangle {
    id: card
    width: layout.implicitWidth + Style.space(14)
    height: layout.implicitHeight + Style.space(10)
    radius: Math.max(Style.space(8), Style.cornerRadius)
    color: Color.menu.background
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(Color.menu.border, 0.5)

    opacity: root.reveal
    scale: 0.97 + 0.03 * root.reveal
    transformOrigin: Item.Bottom

    RowLayout {
      id: layout
      anchors.centerIn: parent
      spacing: Style.space(3)

      Repeater {
        model: root.tools

        delegate: Rectangle {
          id: toolButton
          required property var modelData

          readonly property bool current: root.tool === modelData.key

          width: Style.space(30)
          height: Style.space(30)
          radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
          color: current
            ? Util.alpha(Color.accent, 0.16)
            : (toolArea.containsMouse ? Color.menu.selectedBackground : "transparent")
          border.width: current ? Math.max(1, Style.space(1)) : 0
          border.color: Util.alpha(Color.accent, 0.45)

          Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
          }

          Canvas {
            anchors.centerIn: parent
            width: Style.space(16)
            height: Style.space(16)

            property bool active: toolButton.current
            onActiveChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = toolButton.current ? Color.accent : Color.menu.text
              ctx.lineWidth = 1.6
              ctx.lineCap = "round"
              ctx.lineJoin = "round"
              var w = width
              var h = height

              if (toolButton.modelData.key === "pencil") {
                ctx.beginPath()
                ctx.moveTo(w * 0.10, h * 0.90)
                ctx.lineTo(w * 0.24, h * 0.58)
                ctx.lineTo(w * 0.68, h * 0.14)
                ctx.lineTo(w * 0.86, h * 0.32)
                ctx.lineTo(w * 0.42, h * 0.76)
                ctx.closePath()
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(w * 0.24, h * 0.58)
                ctx.lineTo(w * 0.42, h * 0.76)
                ctx.stroke()
              } else if (toolButton.modelData.key === "line") {
                ctx.beginPath()
                ctx.moveTo(w * 0.18, h * 0.82)
                ctx.lineTo(w * 0.82, h * 0.18)
                ctx.stroke()
              } else if (toolButton.modelData.key === "rect") {
                ctx.strokeRect(w * 0.18, h * 0.28, w * 0.64, h * 0.44)
              } else {
                ctx.beginPath()
                ctx.moveTo(w * 0.18, h * 0.82)
                ctx.lineTo(w * 0.78, h * 0.22)
                ctx.moveTo(w * 0.5, h * 0.22)
                ctx.lineTo(w * 0.78, h * 0.22)
                ctx.lineTo(w * 0.78, h * 0.5)
                ctx.stroke()
              }
            }
          }

          MouseArea {
            id: toolArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.toolPicked(toolButton.modelData.key)
          }
        }
      }

      Rectangle {
        Layout.preferredWidth: Math.max(1, Style.space(1))
        Layout.preferredHeight: Style.space(18)
        Layout.leftMargin: Style.space(3)
        Layout.rightMargin: Style.space(3)
        color: Util.alpha(Color.menu.text, 0.15)
      }

      Repeater {
        model: root.palette

        delegate: Item {
          id: swatch
          required property var modelData

          readonly property bool current: root.color === modelData

          width: Style.space(24)
          height: Style.space(30)

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(16)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: swatch.current ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
            border.color: swatch.current ? Color.menu.text : Util.alpha(Color.menu.text, 0.25)
          }

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(10)
            height: width
            radius: width / 2
            color: swatch.modelData
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.colorPicked(swatch.modelData)
          }
        }
      }

      Rectangle {
        Layout.preferredWidth: Math.max(1, Style.space(1))
        Layout.preferredHeight: Style.space(18)
        Layout.leftMargin: Style.space(3)
        Layout.rightMargin: Style.space(3)
        color: Util.alpha(Color.menu.text, 0.15)
      }

      // Grosor: el punto muestra el tamaño; clic para el siguiente.
      Rectangle {
        width: Style.space(30)
        height: Style.space(30)
        radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
        color: widthArea.containsMouse ? Color.menu.selectedBackground : "transparent"

        Behavior on color {
          ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(Style.space(16), Style.space(2) + root.strokeWidth * Style.space(1.4))
          height: width
          radius: width / 2
          color: root.color
        }

        MouseArea {
          id: widthArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.widthCycled()
        }
      }

      Text {
        text: "Deshacer"
        color: undoArea.containsMouse ? Color.menu.text : Util.alpha(Color.menu.text, 0.65)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          id: undoArea
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          hoverEnabled: true
          onClicked: root.undoRequested()
        }
      }

      Text {
        text: "Borrar"
        color: clearArea.containsMouse ? Color.menu.text : Util.alpha(Color.menu.text, 0.65)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          id: clearArea
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          hoverEnabled: true
          onClicked: root.clearRequested()
        }
      }
    }
  }
}
