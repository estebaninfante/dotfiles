// bateria-overlay — el aviso de batería baja, como overlay propio.
//
// Lo lanza `omarchy-battery-low` (linux/bin) así:
//
//   BATERIA_NIVEL=5 BATERIA_SEGUNDOS=70 quickshell -n -p <este archivo>
//
// Una tarjeta abajo al centro, click-through salvo la tarjeta: no agarra foco
// ni teclado, no roba el mouse.
//
// Se cierra sola en tres casos: entra corriente (es lo que está pidiendo, así
// que apenas lo conectás se va), se cumple BATERIA_SEGUNDOS, o la tocás. El
// lanzador le pone además un `timeout` duro por si este proceso se cuelga.
//
// Colores del tema actual (galaxy-mono y lo que venga): se leen de
// ~/.local/state/omarchy/current/theme, con fallback a los de Omarchy.

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
  id: root

  readonly property int nivel: Math.max(0, Math.min(100, parseInt(Quickshell.env("BATERIA_NIVEL") || "5", 10)))
  readonly property int segundos: Math.max(5, parseInt(Quickshell.env("BATERIA_SEGUNDOS") || "70", 10))
  readonly property string fuentes: Quickshell.env("BATERIA_FUENTES") || "/sys/class/power_supply"

  // --- tema ---------------------------------------------------------------
  property string tShell: ""
  property string tColors: ""

  function valorToml(texto, seccion, clave) {
    const bloque = new RegExp("\\[" + seccion + "\\]([\\s\\S]*?)(?=\\n\\[|$)").exec(String(texto || ""))
    if (!bloque) return ""
    const linea = new RegExp("^\\s*" + clave + "\\s*=\\s*\"([^\"]+)\"", "m").exec(bloque[1])
    return linea ? linea[1] : ""
  }

  readonly property color fondo: valorToml(tShell, "notifications", "background") || "#1e1e20"
  readonly property color texto: valorToml(tShell, "notifications", "text") || "#f0f0f0"
  readonly property color borde: valorToml(tShell, "notifications", "border") || "#cdcdcd"
  readonly property color acento: valorToml(tShell, "notifications", "countdown")
    || valorToml(tColors, "", "accent") || "#cdcdcd"
  readonly property color alerta: valorToml(tShell, "lock", "text-error") || "#e85a4a"

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/shell.toml"
    printErrors: false
    onLoaded: root.tShell = text()
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.tColors = text()
  }

  // --- vida del aviso -----------------------------------------------------
  property bool abierto: true
  property int restantes: segundos
  property real progreso: 1

  // En qué monitor: el enfocado, o el primero si no hay Hyprland.
  readonly property string pantalla: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

  function cerrar() {
    if (!root.abierto) return
    root.abierto = false
    fin.start()
  }

  Timer {
    id: fin
    interval: 220
    onTriggered: Qt.quit()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.abierto
    onTriggered: {
      root.restantes -= 1
      if (root.restantes <= 0) root.cerrar()
    }
  }

  // Línea de tiempo: el riel de abajo se vacía a ritmo parejo.
  NumberAnimation {
    target: root
    property: "progreso"
    from: 1
    to: 0
    duration: root.segundos * 1000
    running: root.abierto
    easing.type: Easing.Linear
  }

  // ¿Ya está conectado? Basta un `online` en 1 de cualquier fuente que no sea
  // la batería (ADP0, AC0, UC13… cambia según el modelo).
  Process {
    id: corriente
    command: ["sh", "-c",
      "for p in " + root.fuentes + "/*/online; do " +
      "case $p in */BAT*) continue ;; esac; " +
      "[ \"$(cat $p 2>/dev/null)\" = 1 ] && exit 0; done; exit 1"]
    onExited: function (code) { if (code === 0) root.cerrar() }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.abierto
    onTriggered: if (!corriente.running) corriente.running = true
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      required property var modelData
      required property int index

      screen: modelData
      visible: root.pantalla === "" ? index === 0 : modelData.name === root.pantalla

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      color: "transparent"
      exclusiveZone: 0
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "bateria-aviso"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Sólo la tarjeta come clicks; el resto de la capa es transparente al
      // mouse.
      mask: Region { item: tarjeta }

      Rectangle {
        id: tarjeta

        // Entrada: aparece subiendo 12 px.
        property real entrada: 0

        width: 372
        height: 92
        radius: 4
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(76 + (1 - entrada) * 12)

        color: Qt.lighter(root.fondo, hover.hovered ? 1.09 : 1.0)
        border.width: 1
        border.color: Qt.rgba(root.borde.r, root.borde.g, root.borde.b,
                              hover.hovered ? 0.55 : 0.30)
        opacity: root.abierto ? entrada : 0
        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        Component.onCompleted: entradaAnim.start()
        NumberAnimation {
          id: entradaAnim
          target: tarjeta
          property: "entrada"
          from: 0
          to: 1
          duration: 240
          easing.type: Easing.OutCubic
        }

        HoverHandler { id: hover }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cerrar()
        }

        // --- batería dibujada -------------------------------------------
        Item {
          id: pila
          width: 48
          height: 24
          anchors.left: parent.left
          anchors.leftMargin: 18
          anchors.top: parent.top
          anchors.topMargin: 17

          Rectangle {
            id: cuerpo
            width: 44
            height: 24
            radius: 3
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(root.texto.r, root.texto.g, root.texto.b, 0.55)

            // El relleno es el nivel: al 5 % queda una astilla.
            Rectangle {
              x: 4
              y: 4
              height: parent.height - 8
              radius: 1
              width: Math.max(2, (parent.width - 8) * root.nivel / 100)
              color: root.nivel <= 20 ? root.alerta : Qt.rgba(root.texto.r, root.texto.g, root.texto.b, 0.85)
            }
          }

          Rectangle {
            width: 3
            height: 10
            radius: 1.5
            x: cuerpo.width + 1
            anchors.verticalCenter: cuerpo.verticalCenter
            color: Qt.rgba(root.texto.r, root.texto.g, root.texto.b, 0.55)
          }
        }

        Column {
          anchors.left: pila.right
          anchors.leftMargin: 16
          anchors.right: porcentaje.left
          anchors.rightMargin: 14
          anchors.top: parent.top
          anchors.topMargin: 16
          spacing: 3

          Text {
            width: parent.width
            text: "Conecta el cargador"
            elide: Text.ElideRight
            color: root.texto
            font.family: "Liberation Sans"
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }

          Text {
            width: parent.width
            text: "Este aviso se va solo al conectarlo"
            elide: Text.ElideRight
            color: Qt.rgba(root.texto.r, root.texto.g, root.texto.b, 0.62)
            font.family: "Liberation Sans"
            font.pixelSize: 11.5
          }
        }

        // El porcentaje grande: el dato que importa, en su columna.
        Column {
          id: porcentaje
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.top: parent.top
          anchors.topMargin: 13
          spacing: 0

          Text {
            anchors.right: parent.right
            text: root.nivel + "%"
            color: root.nivel <= 20 ? root.alerta : root.texto
            font.family: "Liberation Sans"
            font.pixelSize: 26
            font.weight: Font.DemiBold
          }

          Text {
            anchors.right: parent.right
            text: "BATERÍA"
            color: Qt.rgba(root.texto.r, root.texto.g, root.texto.b, 0.45)
            font.family: "Liberation Sans"
            font.pixelSize: 9
            font.letterSpacing: 1.2
          }
        }

        // --- riel del tiempo --------------------------------------------
        Rectangle {
          id: riel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 18
          anchors.rightMargin: 18
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 14
          height: 2
          color: Qt.rgba(root.texto.r, root.texto.g, root.texto.b, 0.10)

          Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: parent.width * root.progreso
            color: Qt.rgba(root.acento.r, root.acento.g, root.acento.b, 0.75)
          }
        }
      }
    }
  }
}
