import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "motion"

// El laboratorio: cada primitiva del motor, en vivo. Es el criterio de
// aceptación visual y el lugar del que se copian las recetas.
//
// Todo se dispara con un solo `play()`: un gesto, una pieza.
Item {
  id: lab

  property bool running: false
  property bool slow: false       // 4x más lento para mirar de cerca
  property bool animationsOn: true
  property int generation: 0
  signal closeRequested()

  readonly property int unit: Style.font.body
  readonly property real timeScale: slow ? 4 : 1
  readonly property color fg: Commons.Color.menu.text
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property color line: Commons.Color.menu.border
  readonly property color accent: Commons.Color.accent

  function reset() {
    play()
    keys.forceActiveFocus()
  }
  function play() { generation++ }

  // El interruptor maestro es del escritorio, no del laboratorio: acá se
  // prende y se apaga de verdad, para ver el cambio en el acto.
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/animations-enabled"
  FileView {
    path: lab.statePath
    watchChanges: true
    printErrors: false
    onLoaded: lab.animationsOn = text().trim() !== "0"
    onLoadFailed: lab.animationsOn = true
    onFileChanged: reload()
  }

  Process {
    id: setAnim
    property bool value: true
    command: ["sh", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy\" && " +
      "printf '%s\\n' " + (setAnim.value ? "1" : "0") + " > \"$HOME/.local/state/omarchy/animations-enabled\" && " +
      "hyprctl eval 'hl.config({ animations = { enabled = " + (setAnim.value ? "true" : "false") + " } })'"]
    onExited: {
      lab.animationsOn = setAnim.value
      lab.play()
    }
  }
  function setAnimations(on) {
    setAnim.value = on
    setAnim.running = false
    setAnim.running = true
  }

  // ---------------------------------------------------------------- layout
  Column {
    anchors.fill: parent

    // Encabezado
    Item {
      width: parent.width
      height: Math.round(lab.unit * 5.4)

      Row {
        x: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(14)

        Text {
          text: ""
          font.family: "omarchy"
          font.pixelSize: Style.font.displayLarge + Style.space(10)
          color: lab.accent
          anchors.verticalCenter: parent.verticalCenter
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)
          Text {
            text: "Motion"
            color: lab.fg
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            text: "El movimiento del escritorio, en una sola pieza"
            color: lab.dim
            font.family: Style.font.resolvedFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        text: (Tokens.reduced ? "sin animaciones" : (lab.slow ? "lento · 4x" : "normal"))
        color: lab.dim
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Ui.PanelSeparator { foreground: lab.fg }

    // Escenario: cuatro tiles en 2x2, todos disparados por el mismo "play".
    Item {
      id: stage
      width: parent.width
      height: parent.height - Math.round(lab.unit * 5.4) - Math.round(lab.unit * 3.2) - 2

      Grid {
        id: grid
        anchors.fill: parent
        anchors.margins: Style.space(8)
        columns: 2
        spacing: Style.space(8)
        property real cw: (width - spacing) / 2
        property real ch: (height - spacing) / 2

        // ---------------------------------------------------------- Reveal
        Tile {
          id: revealTile
          width: grid.cw
          height: grid.ch
          title: "Reveal"
          hint: "entra y sale pareado · nunca de golpe"
          onPlay: { shown = !shown; if (!shown) revealBack.restart() }

          property bool shown: true
          property int count: 6
          Timer { id: revealBack; interval: 1800; onTriggered: revealTile.shown = true }

          Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: Style.space(6)
            Repeater {
              model: 6
              delegate: Reveal {
                required property int index
                width: Math.round(lab.unit * 3.4)
                height: Math.round(lab.unit * 2.4)
                shown: revealTile.shown
                delay: Math.round(Tokens.delayFor(index) * lab.timeScale)
                duration: Math.round(Tokens.base * lab.timeScale)
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: Commons.Util.alpha(lab.accent, 0.16)
                  border.width: 1
                  border.color: Commons.Util.alpha(lab.accent, 0.5)
                }
              }
            }
          }
        }

        // --------------------------------------------------------- Stagger
        Tile {
          id: staggerTile
          width: grid.cw
          height: grid.ch
          title: "Stagger"
          hint: "una entrada, un barrido · la dirección sigue al gesto"
          onPlay: {
            backward = !backward
            shown = !shown
            if (!shown) staggerBack.restart()
          }

          property bool shown: true
          property bool backward: false
          property int count: 14
          Timer { id: staggerBack; interval: 1600; onTriggered: staggerTile.shown = true }

          Row {
            anchors.centerIn: parent
            spacing: Math.max(2, Style.space(3))
            Repeater {
              model: 14
              delegate: Reveal {
                required property int index
                width: Math.max(3, Math.round(lab.unit * 0.55))
                height: Math.round(lab.unit * (1.2 + 2.6 * Math.abs(Math.sin(index * 1.7))))
                shown: staggerTile.shown
                delay: Math.round(Tokens.delayFor(staggerTile.backward ? staggerTile.count - 1 - index : index) * lab.timeScale)
                duration: Math.round(Tokens.base * lab.timeScale)
                rise: 8
                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: Commons.Util.alpha(lab.accent, 0.35 + 0.5 * index / 14)
                }
              }
            }
          }
        }

        // ----------------------------------------------------------- Morph
        Tile {
          id: morphTile
          width: grid.cw
          height: grid.ch
          title: "Morph"
          hint: "una forma, dos proyecciones · el medio es el gesto"
          onPlay: morph.go(morph.progress > 0.5 ? 0 : 1)

          property var weights: []
          readonly property int rings: 7
          readonly property int perRing: 20
          readonly property int total: rings * perRing

          function dotX(i) {
            var idx = i % perRing, ring = Math.floor(i / perRing)
            var k = weights[ring] === undefined ? 0 : weights[ring]
            var row = width * 0.14 + idx / (perRing - 1) * width * 0.72
            var r = Math.min(width, height) * 0.44 * (0.18 + 0.82 * ring / (rings - 1))
            var cir = width / 2 + Math.cos(idx / perRing * Math.PI * 2) * r
            return row + (cir - row) * k
          }
          function dotY(i) {
            var idx = i % perRing, ring = Math.floor(i / perRing)
            var k = weights[ring] === undefined ? 0 : weights[ring]
            var row = height * 0.16 + ring / (rings - 1) * height * 0.68
            var r = Math.min(width, height) * 0.44 * (0.18 + 0.82 * ring / (rings - 1))
            var cir = height / 2 + Math.sin(idx / perRing * Math.PI * 2) * r
            return row + (cir - row) * k
          }

          Morph {
            id: morph
            count: morphTile.rings
            duration: Math.round(Tokens.morph * lab.timeScale)
            step: Math.round(Tokens.staggerStepMorph * lab.timeScale)
            onTick: function(t) {
              var w = []
              for (var i = 0; i < morphTile.rings; i++) w.push(morph.weight(i))
              morphTile.weights = w
            }
            Component.onCompleted: {
              var w = []
              for (var i = 0; i < morphTile.rings; i++) w.push(1)
              morphTile.weights = w
            }
          }

          Repeater {
            model: morphTile.total
            delegate: Rectangle {
              required property int index
              readonly property int ring: Math.floor(index / morphTile.perRing)
              width: 4; height: 4; radius: 2
              x: morphTile.dotX(index) - 2
              y: morphTile.dotY(index) - 2
              color: Commons.Util.alpha(lab.accent, 0.25 + 0.75 * ring / (morphTile.rings - 1))
            }
          }
        }

        // ---------------------------------------------------------- Spring
        Tile {
          id: springTile
          width: grid.cw
          height: grid.ch
          title: "Spring"
          hint: "arrastrá y soltá · vuelve con la física del sistema"
          onPlay: { spring.stop(); spring.start() }

          Item {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Math.round(lab.unit * 3)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: 1
              color: Commons.Util.alpha(lab.fg, 0.18)
            }

            Rectangle {
              id: pill
              x: track.width / 2 - width / 2
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(lab.unit * 2.2)
              height: width
              radius: width / 2
              color: Commons.Util.alpha(lab.accent, 0.85)

              SpringAnimation on x {
                id: spring
                spring: Tokens.springStiffness
                damping: Tokens.springDamping
                mass: Tokens.springMass
                epsilon: Tokens.springEpsilon
                to: track.width / 2 - pill.width / 2
              }

              Component.onCompleted: pill.x = track.width / 2 - pill.width / 2
              Connections {
                target: track
                function onWidthChanged() { if (!spring.running) pill.x = track.width / 2 - pill.width / 2 }
              }

              MouseArea {
                anchors.fill: parent
                drag.target: pill
                drag.axis: Drag.XAxis
                drag.minimumX: 0
                drag.maximumX: track.width - pill.width
                onPressed: spring.stop()
                onReleased: { spring.stop(); spring.start() }
              }
            }
          }
        }
      }
    }

    Ui.PanelSeparator { foreground: lab.fg }

    // Pie: el gesto, y el interruptor real del escritorio.
    Item {
      width: parent.width
      height: Math.round(lab.unit * 3.2)

      Text {
        x: Style.space(14)
        width: parent.width - buttons.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: "R o Espacio: otra vez · Esc: cerrar · arrastrá el resorte"
        color: lab.dim
        font.family: Style.font.resolvedFamily
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Ui.Button {
          text: "Lento"
          bordered: true
          selected: lab.slow
          fontSize: Style.font.bodySmall
          onClicked: { lab.slow = !lab.slow; lab.play() }
        }
        Ui.Button {
          text: lab.animationsOn ? "Animaciones: sí" : "Animaciones: no"
          bordered: true
          selected: !lab.animationsOn
          fontSize: Style.font.bodySmall
          onClicked: lab.setAnimations(!lab.animationsOn)
        }
        Ui.Button {
          text: "Otra vez"
          bordered: true
          fontSize: Style.font.bodySmall
          onClicked: lab.play()
        }
      }
    }
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) { lab.closeRequested(); event.accepted = true }
      else if (event.key === Qt.Key_Space || event.key === Qt.Key_R) { lab.play(); event.accepted = true }
    }
  }

  // ------------------------------------------------------------------ typos
  component Tile: Rectangle {
    id: tile
    property string title: ""
    property string hint: ""
    signal play()

    // Un solo gesto mueve todo: el play del laboratorio entra acá.
    Connections {
      target: lab
      function onGenerationChanged() { tile.play() }
    }

    color: Commons.Util.alpha(Commons.Color.menu.background, 0.5)
    radius: Style.cornerRadius
    border.width: 1
    border.color: Commons.Util.alpha(tile.line, 0.6)

    default property alias body: bodyItem.data

    Item {
      id: bodyItem
      anchors.fill: parent
      anchors.margins: Style.space(10)
      anchors.topMargin: Math.round(lab.unit * 3.2)
    }

    Text {
      x: Style.space(10)
      y: Style.space(8)
      text: tile.title
      color: lab.fg
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      x: Style.space(10)
      y: Style.space(8) + Math.round(lab.unit * 1.5)
      width: parent.width - 2 * Style.space(10)
      elide: Text.ElideRight
      text: tile.hint
      color: lab.dim
      font.family: Style.font.resolvedFamily
      font.pixelSize: Style.font.bodySmall
    }

    // El encabezado del tile es el disparador; el cuerpo queda libre para
    // arrastrar (el resorte) sin que un MouseArea se coma el gesto.
    MouseArea {
      x: 0; y: 0
      width: parent.width
      height: Math.round(lab.unit * 3.1)
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.play()
    }
  }
}
