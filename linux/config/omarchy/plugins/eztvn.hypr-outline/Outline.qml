import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Menú radial en la pantalla de la compu, espejo del que se maneja con el dedo
// en la tablet: las mismas opciones, en las mismas direcciones, resaltando lo
// que está elegido.
//
// No recibe clics: solo se mira. El shell lo muestra con summon (y le pasa la
// selección en el payload, así aparece al instante) y lo esconde con hide;
// mientras está abierto, consulta el estado seguido para seguir el recorrido.
Item {
  id: root

  property var menu: []
  property bool abierto: false
  property string sel: ""
  property string hijo: ""
  property int base: 0

  // Todo proporcional al tamaño de la pantalla, para que se lea de lejos.
  readonly property real escala: Math.max(700, Math.min(panel.width, panel.height))
  readonly property real radio: escala * 0.20
  readonly property real radioHijo: radio * 1.38
  readonly property real lado: radio * 0.54
  readonly property real ladoHijo: lado * 0.84
  readonly property real fuenteIcono: lado * 0.30
  readonly property real fuenteTexto: lado * 0.18
  readonly property real fuenteGlobo: lado * 0.24

  readonly property var madreElegida: buscar(sel)
  readonly property var hijoElegido: madreElegida && madreElegida.hijos
    ? buscarHijo(madreElegida, hijo) : null
  readonly property int abanico: 55

  readonly property string globo: {
    if (!madreElegida) return ""
    var t = madreElegida.icono + "  " + madreElegida.texto
    if (hijoElegido) t += "   ›   " + hijoElegido.icono + "  " + hijoElegido.texto
    return t
  }

  // El shell llama a estas dos al mostrarlo y esconderlo.
  function open(payload) {
    if (payload) {
      try {
        var a = JSON.parse(payload)
        if (a && a.sel !== undefined) sel = a.sel || ""
        if (a && a.hijo !== undefined) hijo = a.hijo || ""
        if (a && a.base !== undefined) base = a.base || 0
      } catch (e) {}
    }
    abierto = true
    leer.running = true
  }

  function close() {
    abierto = false
  }

  function buscar(id) {
    for (var i = 0; i < root.menu.length; i++) {
      if (root.menu[i].id === id) return root.menu[i]
    }
    return null
  }

  function buscarHijo(madre, id) {
    if (!madre || !madre.hijos) return null
    for (var i = 0; i < madre.hijos.length; i++) {
      if (madre.hijos[i].id === id) return madre.hijos[i]
    }
    return null
  }

  function aRadianes(grados) {
    return (grados - 90) * Math.PI / 180
  }

  function posX(grados, r) {
    return panel.width / 2 + Math.cos(aRadianes(grados)) * r
  }

  function posY(grados, r) {
    return panel.height / 2 + Math.sin(aRadianes(grados)) * r
  }

  function anguloDe(item) {
    return ((item.ang + root.base) % 360 + 360) % 360
  }

  function angulosHijos(madre) {
    var n = madre.hijos.length
    var salida = []
    var centro = (n - 1) / 2
    var paso = n > 1 ? (root.abanico * 2) / (n - 1) : 0
    for (var i = 0; i < n; i++) {
      salida.push(((root.anguloDe(madre) + (i - centro) * paso) % 360 + 360) % 360)
    }
    return salida
  }

  // El menú se pide del hub de hypr-remote (su socket de control) y, si no
  // está, del servidor hypr-outline de siempre. Así el espejo funciona con
  // cualquiera de los dos, sin depender de quién lo dispare.
  readonly property string fuenteEstado: "out=$(curl -s --max-time 3 --unix-socket \"${XDG_RUNTIME_DIR}/hypr-remote/control.sock\" http://localhost/radial 2>/dev/null); if [ -z \"$out\" ]; then curl -s --max-time 3 http://127.0.0.1:1781/api/radial; else printf '%s' \"$out\"; fi"
  readonly property string fuenteMenu: "out=$(curl -s --max-time 3 --unix-socket \"${XDG_RUNTIME_DIR}/hypr-remote/control.sock\" http://localhost/radial 2>/dev/null); if [ -z \"$out\" ]; then curl -s --max-time 3 http://127.0.0.1:1781/api/menu; else printf '%s' \"$out\"; fi"

  // Acepta las dos formas: solo el menú (array) o menú + selección (objeto).
  function aplicarRadial(d) {
    if (!d) return
    if (Array.isArray(d)) { root.menu = d; return }
    if (Array.isArray(d.menu)) root.menu = d.menu
    root.sel = d.sel || ""
    root.hijo = d.hijo || ""
    root.base = d.base || 0
    if (d.abierto === true) root.abierto = true
    else if (d.abierto === false) root.abierto = false
  }

  Process {
    id: pedirMenu
    running: true
    command: ["bash", "-lc", root.fuenteMenu]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.aplicarRadial(JSON.parse(text))
        } catch (e) {
          console.log("hypr-outline: no pude leer el menú:", e)
        }
      }
    }
  }

  // Mientras está abierto, se sigue la selección.
  Process {
    id: leer
    running: false
    command: ["bash", "-lc", root.fuenteEstado]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.aplicarRadial(JSON.parse(text))
        } catch (e) {}
      }
    }
  }

  // Se sondea siempre: cuando está cerrado, espaciado; abierto, seguido. Así el
  // espejo aparece solo, sin que ningún servidor tenga que avisarle.
  Timer {
    running: true
    repeat: true
    interval: root.abierto ? 110 : 350
    onTriggered: if (!leer.running) leer.running = true
  }

  PanelWindow {
    id: panel

    visible: root.abierto
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "hypr-outline-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}                     // solo se mira: los clics pasan de largo

    Rectangle {
      anchors.fill: parent
      color: "transparent"
    }

    Rectangle {
      width: root.radio * 2
      height: root.radio * 2
      radius: root.radio
      x: parent.width / 2 - root.radio
      y: parent.height / 2 - root.radio
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(Color.popups.text, 0.18)
    }

    Rectangle {
      visible: root.madreElegida !== null && root.madreElegida.hijos !== undefined
      width: root.radioHijo * 2
      height: root.radioHijo * 2
      radius: root.radioHijo
      x: parent.width / 2 - root.radioHijo
      y: parent.height / 2 - root.radioHijo
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.25)
    }

    Repeater {
      model: root.menu

      delegate: Item {
        required property var modelData

        readonly property bool elegida: root.sel === modelData.id

        width: root.lado
        height: root.lado
        x: root.posX(root.anguloDe(modelData), root.radio) - root.lado / 2
        y: root.posY(root.anguloDe(modelData), root.radio) - root.lado / 2

        Column {
          anchors.centerIn: parent
          spacing: 2

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.icono
            color: parent.parent.elegida ? Color.accent : "white"
            font.pixelSize: root.fuenteIcono
            style: Text.Outline
            styleColor: "#000000d9"
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.texto
            color: parent.parent.elegida ? Color.accent : Util.alpha("white", 0.92)
            font.pixelSize: root.fuenteTexto
            style: Text.Outline
            styleColor: "#000000d9"
          }
        }
      }
    }

    Repeater {
      model: root.madreElegida !== null && root.madreElegida.hijos !== undefined
        ? root.madreElegida.hijos
        : []

      delegate: Item {
        required property var modelData
        required property int index

        readonly property var angulos: root.angulosHijos(root.madreElegida)
        readonly property bool elegida: root.hijo === modelData.id

        width: root.ladoHijo
        height: root.ladoHijo
        x: root.posX(angulos[index], root.radioHijo) - root.ladoHijo / 2
        y: root.posY(angulos[index], root.radioHijo) - root.ladoHijo / 2

        Column {
          anchors.centerIn: parent
          spacing: 1

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.icono
            color: parent.parent.elegida ? Color.accent : "white"
            font.pixelSize: root.fuenteIcono * 0.9
            style: Text.Outline
            styleColor: "#000000d9"
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.texto || ""
            color: parent.parent.elegida ? Color.accent : Util.alpha("white", 0.86)
            font.pixelSize: root.fuenteTexto * 0.9
            style: Text.Outline
            styleColor: "#000000d9"
          }
        }
      }
    }

    Rectangle {
      visible: root.globo !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 + root.radioHijo + Style.space(26)
      width: textoGlobo.implicitWidth + Style.space(40)
      height: textoGlobo.implicitHeight + Style.space(20)
      radius: height / 2
      color: Util.alpha(Color.background, 0.94)
      border.width: 2
      border.color: Util.alpha(Color.accent, 0.7)

      Text {
        id: textoGlobo
        anchors.centerIn: parent
        text: root.globo
        color: Color.popups.text
        font.pixelSize: root.fuenteGlobo
      }
    }

    Text {
      visible: root.globo === ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 + Style.space(40)
      text: "elegí recorriendo con el dedo"
      color: Util.alpha(Color.popups.text, 0.6)
      font.pixelSize: Style.font.caption
    }
  }
}
