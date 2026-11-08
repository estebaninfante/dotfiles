import QtQuick
import QtQuick.Layouts
import qs.Commons

// Barra flotante única del menú de captura: cada acción con icono, nombre y
// para qué sirve; el cursor y las flechas mueven la selección y Enter (o 1-6)
// la ejecuta. En modo región se oculta al arrastrar y su pie explica el gesto.
Item {
  id: root

  property var rows: []
  property int currentIndex: 0
  property real reveal: 0
  property bool regionMode: false
  signal activated(int index)
  signal hovered(int index)

  implicitWidth: card.width
  implicitHeight: card.height

  Rectangle {
    id: card
    width: layout.implicitWidth + Style.space(20)
    height: layout.implicitHeight + Style.space(16)
    radius: Math.max(Style.space(8), Style.cornerRadius)
    color: Color.menu.background
    border.width: Math.max(1, Style.space(1))
    border.color: Util.alpha(Color.menu.border, 0.5)

    opacity: root.reveal
    scale: 0.97 + 0.03 * root.reveal
    transformOrigin: Item.Top

    ColumnLayout {
      id: layout
      anchors.centerIn: parent
      spacing: Style.space(8)

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.space(4)

        Repeater {
          model: root.rows

          delegate: Rectangle {
            id: button
            required property var modelData
            required property int index

            readonly property bool current: index === root.currentIndex

            width: Style.space(92)
            height: Style.space(62)
            radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(4))
            color: current
              ? Util.alpha(Color.accent, 0.16)
              : (hover.containsMouse ? Color.menu.selectedBackground : "transparent")
            border.width: current ? Math.max(1, Style.space(1)) : 0
            border.color: Util.alpha(Color.accent, 0.45)

            Behavior on color {
              ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(1)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: button.modelData.icon
                color: button.current ? Color.accent : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.iconLarge
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: button.modelData.label
                color: button.current ? Color.accent : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: button.current
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: button.modelData.caption
                color: Util.alpha(Color.menu.text, button.current ? 0.75 : 0.45)
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Punto rojo: estas filas graban, no sólo capturan.
            Rectangle {
              visible: button.modelData.record === true
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(7)
              width: Style.space(6)
              height: width
              radius: width / 2
              color: Color.urgent
            }

            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.hovered(button.index)
              onClicked: root.activated(button.index)
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(1, Style.space(1))
        color: Util.alpha(Color.menu.text, 0.12)
      }

      Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.regionMode
          ? "Arrastra una zona o clic en una ventana  ·  Esc cancela"
          : "← →  mover    ·    Enter  aceptar    ·    Esc  cancelar"
        color: Util.alpha(Color.menu.text, 0.45)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
