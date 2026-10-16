import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Menú radial en la pantalla de la compu, espejo del que se usa con el dedo en
// la tablet. No recibe clics: solo se mira. El estado llega por el flujo de
// eventos del servidor hypr-outline (una sola conexión, sin sondear).
Item {
  id: root

  property var menu: []
  property bool abierto: false
  property string sel: ""
  property string hijo: ""
  property int base: 0

  readonly property int radio: 138
  readonly property int radioHijo: 200
  readonly property int abanico: 55
  readonly property int lado: 76
  readonly property int ladoHijo: 62

  readonly property var madreElegida: buscar(sel)
  readonly property var hijoElegido: madreElegida && madreElegida.hijos ? buscarHijo(madreElegida, hijo) : null
  readonly property string globo: {
    if (!madreElegida) return "";
    var t = madreElegida.icono + "  " + madreElegida.texto;
    if (hijoElegido) t += "   ›   " + hijoElegido.icono + "  " + hijoElegido.texto;
    return t;
  }

  function buscar(id) {
    for (var i = 0; i < root.menu.length; i++) {
      if (root.menu[i].id === id) return root.menu[i];
    }
    return null;
  }

  function buscarHijo(madre, id) {
    if (!madre || !madre.hijos) return null;
    for (var i = 0; i < madre.hijos.length; i++) {
      if (madre.hijos[i].id === id) return madre.hijos[i];
    }
    return null;
  }

  function aRadianes(grados) {
    return (grados - 90) * Math.PI / 180;
  }

  function posX(grados, r) {
    return root.width / 2 + Math.cos(aRadianes(grados)) * r;
  }

  function posY(grados, r) {
    return root.height / 2 + Math.sin(aRadianes(grados)) * r;
  }

  function anguloDe(item) {
    return ((item.ang + root.base) % 360 + 360) % 360;
  }

  function angulosHijos(madre) {
    var n = madre.hijos.length;
    var salida = [];
    var centro = (n - 1) / 2;
    var paso = n > 1 ? (root.abanico * 2) / (n - 1) : 0;
    for (var i = 0; i < n; i++) {
      salida.push(((root.anguloDe(madre) + (i - centro) * paso) % 360 + 360) % 360);
    }
    return salida;
  }

  // El menú se pide una sola vez.
  Process {
    id: pedirMenu
    running: true
    command: ["curl", "-s", "--max-time", "3", "http://127.0.0.1:1781/api/menu"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var datos = JSON.parse(text);
          if (Array.isArray(datos)) root.menu = datos;
        } catch (e) {
          console.log("hypr-outline: no pude leer el menú:", e);
        }
      }
    }
  }

  // Y el estado en vivo: una sola conexión abierta al flujo de eventos.
  Process {
    id: escuchar
    running: true
    command: ["curl", "-N", "-s", "http://127.0.0.1:1781/api/eventos"]
    stdout: SplitParser {
      onRead: line => {
        console.log("hypr-outline leyo: [" + line.substring(0, 70) + "]");
        if (line.indexOf("data: ") !== 0) return;
        try {
          var d = JSON.parse(line.substring(6));
          if (d.radial) {
            root.abierto = d.radial.abierto === true;
            root.sel = d.radial.sel || "";
            root.hijo = d.radial.hijo || "";
            root.base = d.radial.base || 0;
          }
        } catch (e) {}
      }
    }
    onExited: reintentar.restart()
  }

  Timer {
    id: reintentar
    interval: 1500
    onTriggered: escuchar.running = true
  }

  PanelWindow {
    id: panel

    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "hypr-outline-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}                     // solo se mira: los clics pasan de largo

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.42)
    }

    // Aro guía del anillo principal.
    Rectangle {
      width: root.radio * 2
      height: root.radio * 2
      radius: root.radio
      x: parent.width / 2 - root.radio
      y: parent.height / 2 - root.radio
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(Color.popups.text, 0.15)
    }

    // Aro del submenú, solo cuando hay uno abierto.
    Rectangle {
      visible: root.madreElegida !== null && root.madreElegida.hijos !== undefined
      width: root.radioHijo * 2
      height: root.radioHijo * 2
      radius: root.radioHijo
      x: parent.width / 2 - root.radioHijo
      y: parent.height / 2 - root.radioHijo
      color: "transparent"
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.22)
    }

    // Las opciones del anillo principal.
    Repeater {
      model: root.menu

      delegate: Item {
        required property var modelData

        readonly property bool elegida: root.sel === modelData.id

        width: root.lado
        height: root.lado
        x: root.posX(root.anguloDe(modelData), root.radio) - root.lado / 2
        y: root.posY(root.anguloDe(modelData), root.radio) - root.lado / 2

        Rectangle {
          id: circulo
          anchors.fill: parent
          radius: width / 2
          color: parent.elegida
            ? Util.alpha(Color.accent, 0.92)
            : Util.alpha(Color.popups.background, 0.80)
          border.width: parent.elegida ? 2 : 1
          border.color: parent.elegida
            ? Color.accent
            : Util.alpha(Color.popups.text, 0.25)

          Column {
            anchors.centerIn: parent
            spacing: 1

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.icono
              color: parent.parent.elegida ? Color.background : Color.popups.text
              font.pixelSize: Style.font.display
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.texto
              color: parent.parent.elegida
                ? Util.alpha(Color.background, 0.85)
                : Util.alpha(Color.popups.text, 0.75)
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    // Las opciones del submenú elegido.
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

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: parent.elegida
            ? Util.alpha(Color.accent, 0.92)
            : Util.alpha(Color.popups.background, 0.80)
          border.width: parent.elegida ? 2 : 1
          border.color: parent.elegida
            ? Color.accent
            : Util.alpha(Color.popups.text, 0.25)

          Text {
            anchors.centerIn: parent
            text: modelData.icono
            color: parent.elegida ? Color.background : Color.popups.text
            font.pixelSize: Style.font.display
          }
        }
      }
    }

    // Lo que está elegido, escrito bien claro.
    Rectangle {
      visible: root.globo !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 + root.radioHijo + Style.space(24)
      width: textoGlobo.implicitWidth + Style.space(36)
      height: textoGlobo.implicitHeight + Style.space(20)
      radius: height / 2
      color: Util.alpha(Color.background, 0.92)
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.65)

      Text {
        id: textoGlobo
        anchors.centerIn: parent
        text: root.globo
        color: Color.popups.text
        font.pixelSize: Style.font.title
      }
    }

    Text {
      visible: root.globo === ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 + Style.space(40)
      text: "elegí recorriendo con el dedo"
      color: Util.alpha(Color.popups.text, 0.55)
      font.pixelSize: Style.font.caption
    }
  }
}
