import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

Panel {
  id: root
  moduleName: "eztvn.timer"
  ipcTarget: ""
  manageIpc: false

  property var hostWidget: null
  property var anchorItem: null

  readonly property var widget: hostWidget
  readonly property bool timerActive: root.widget ? root.widget.timerActive === true : false
  readonly property bool eyeActive: root.widget ? root.widget.eyeActive === true : false
  readonly property double timerRemainingMs: root.widget ? root.widget.timerRemainingMs : 0
  readonly property double eyeRemainingMs: root.widget ? root.widget.eyeRemainingMs : 0
  readonly property int eyeMinutes: root.widget ? root.widget.eyeMinutes : 20

  property int minutes: 25

  function startTimer() {
    if (!root.widget) return
    root.widget.startTimer(root.minutes)
    root.minutes = root.widget.timerMinutes
  }

  function toggleEye() {
    if (root.widget) root.widget.toggleEye()
  }

  // El descanso cubre la pantalla: el panel sobra debajo del overlay.
  onEyeActiveChanged: if (root.eyeActive) root.close()

  onOpenedChanged: {
    if (!root.opened || !root.widget) return
    root.minutes = root.widget.timerMinutes
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Connections {
    target: root
    function onMinutesChanged() {
      if (minutesField.field && minutesField.field.value !== root.minutes)
        minutesField.field.value = root.minutes
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: Style.space(340)
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      blocked: minutesField.field.activeFocus
      onCloseRequested: root.close()

      Column {
        id: body
        width: parent.width
        spacing: Style.space(12)

        Text {
          text: "󰔛  Temporizador"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.timerActive
            ? "Cuenta atrás en marcha. Aviso al terminar."
            : "Elige los minutos y arranca la cuenta atrás."
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          visible: root.timerActive
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: Format.clock(root.timerRemainingMs)
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }

          Button {
            text: "Cancelar temporizador"
            bordered: true
            onClicked: if (root.widget) root.widget.stopTimer()
          }
        }

        Column {
          visible: !root.timerActive
          width: parent.width
          spacing: Style.space(10)

          NumberField {
            id: minutesField
            label: "Minutos"
            from: 1
            to: 240
            stepSize: 1
            value: root.minutes
            foreground: Color.foreground
            onModified: function(value) { root.minutes = value }
          }

          Row {
            spacing: Style.space(6)

            Repeater {
              model: [5, 10, 15, 20, 25, 30]

              Button {
                required property int modelData
                text: modelData + "m"
                selected: root.minutes === modelData
                bordered: true
                fontSize: Style.font.caption
                hasCursor: false
                onClicked: root.minutes = modelData
              }
            }
          }

          Button {
            text: "Iniciar temporizador"
            bordered: true
            width: parent.width
            onClicked: root.startTimer()
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: Color.foreground
        }

        Toggle {
          width: parent.width
          label: "Descanso visual"
          description: root.eyeActive
            ? "Quedan " + Format.clock(root.eyeRemainingMs) + " · pantalla cubierta"
            : "Cubre la pantalla " + root.eyeMinutes + " min para mirar lejos"
          checked: root.eyeActive
          onClicked: root.toggleEye()
        }
      }
    }
  }
}
