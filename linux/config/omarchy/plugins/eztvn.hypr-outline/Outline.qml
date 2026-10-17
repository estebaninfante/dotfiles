import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "components"

// Espejo en la pantalla de la compu del menú radial que se maneja con el dedo
// en la tablet: mismas opciones, mismas direcciones, resaltando lo elegido.
//
// Es solo lectura (no recibe clics). El shell lo muestra con summon y lo
// esconde con hide; mientras está abierto, consulta el estado seguido para
// seguir el recorrido del dedo.
//
// Estética: placas de vidrio por opción, halos y arcos HUD. El menú aparece
// seco (sin animación de entrada); lo que se mueve es la selección: las
// placas cambian de color y escala, el arco de foco gira hasta la opción, una
// chispa viaja del centro al elegido y el núcleo late.
Item {
  id: root

  property var menu: []
  property string firmaMenu: ""
  property bool abierto: false
  property string sel: ""
  property string hijo: ""
  property int base: 0
  property string fontFamily: Style.font.menuFamily
  property string pendingInitialMenu: "root"

  // Animaciones de selección habilitadas un instante después de abrir, para
  // que el menú no "entre" animándose.
  property bool animarSeleccion: false

  // Todo proporcional a la pantalla, para que se lea de lejos.
  readonly property real escala: Math.max(700, Math.min(panel.width, panel.height))
  readonly property real radio: escala * 0.20
  readonly property real radioHijo: radio * 1.48
  readonly property real lado: radio * 0.56
  readonly property real ladoHijo: lado * 0.72
  readonly property real fuenteIcono: lado * 0.36
  readonly property real fuenteTexto: lado * 0.155
  readonly property real fuenteGlobo: lado * 0.19

  readonly property color acento: Color.accent
  readonly property color tinta: Color.popups.text
  readonly property color fondo: Color.background
  readonly property int msRapido: 170
  readonly property int msMedio: 240

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

  function open(payload) {
    if (payload) {
      try {
        var a = JSON.parse(payload)
        if (a && a.sel !== undefined) sel = a.sel || ""
        if (a && a.hijo !== undefined) hijo = a.hijo || ""
        if (a && a.base !== undefined) base = a.base || 0
      } catch (e) {}
    }
    animarSeleccion = false
    entradaAnim.restart()
    abierto = true
    leer.running = true
  }

  function close() {
    abierto = false
    animarSeleccion = false
  }

  // Solo reemplaza el menu si de verdad cambio: el poll repite la misma lista
  // cada 110 ms y reasignarla reconstruiria las placas en cada vuelta.
  function ponerMenu(lista) {
    var firma = JSON.stringify(lista)
    if (firma === root.firmaMenu) return
    root.firmaMenu = firma
    root.menu = lista
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

  function indiceHijoElegido() {
    var m = root.madreElegida
    if (!m || !m.hijos) return -1
    for (var i = 0; i < m.hijos.length; i++) {
      if (m.hijos[i].id === root.hijo) return i
    }
    return -1
  }

  function anguloHijoElegido() {
    var i = indiceHijoElegido()
    if (i < 0) return 0
    return angulosHijos(root.madreElegida)[i]
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
      salida.push(((anguloDe(madre) + (i - centro) * paso) % 360 + 360) % 360)
    }
    return salida
  }

  // El menú se pide del hub de hypr-remote (su socket de control) y, si no
  // está, del servidor hypr-outline de siempre. Así el espejo funciona con
  // cualquiera de los dos, sin depender de quién lo dispare.
  readonly property string fuenteEstado: "out=$(curl -s --max-time 3 --unix-socket \"${XDG_RUNTIME_DIR}/hypr-remote/control.sock\" http://localhost/radial 2>/dev/null); if [ -z \"$out\" ]; then curl -s --max-time 3 http://127.0.0.1:1781/api/radial; else printf '%s' \"$out\"; fi"
  readonly property string fuenteMenu: "out=$(curl -s --max-time 3 --unix-socket \"${XDG_RUNTIME_DIR}/hypr-remote/control.sock\" http://localhost/radial 2>/dev/null); if [ -z \"$out\" ]; then curl -s --max-time 3 http://127.0.0.1:1781/api/menu; else printf '%s' \"$out\"; fi"

  // Acepta las dos formas: solo el menú (array) o menú + selección (objeto).
  function animarCambio() {
    if (!root.animarSeleccion || !root.abierto) return
    pulso.restart()
    ondaNucleoCrece.restart()
    ondaNucleoFade.restart()
    chispa.avance = 0
    viaje.restart()
  }

  function aplicarRadial(d) {
    if (!d) return
    if (Array.isArray(d)) { root.ponerMenu(d); return }
    if (Array.isArray(d.menu)) root.ponerMenu(d.menu)
    root.sel = d.sel || ""
    root.hijo = d.hijo || ""
    root.base = d.base || 0
    if (d.abierto === true) root.abierto = true
    else if (d.abierto === false) root.abierto = false
  }

  Timer {
    id: entradaAnim
    interval: 260
    onTriggered: root.animarSeleccion = root.abierto
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

    // Velo: separa el menú del escritorio sin taparlo del todo.
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(root.fondo, 0.66)
    }

    // ── Aros base ─────────────────────────────────────────────────────────
    HudRing {
      anchors.centerIn: parent
      radio: root.radio
      color: Util.alpha(root.tinta, 0.10)
    }

    HudRing {
      anchors.centerIn: parent
      radio: root.radio * 1.07
      color: Util.alpha(root.acento, 0.20)
      punteado: true

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: 120000
        loops: Animation.Infinite
        running: root.abierto
      }
    }

    HudRing {
      anchors.centerIn: parent
      radio: root.radioHijo
      visible: root.madreElegida !== null
      color: Util.alpha(root.acento, 0.16)
    }

    // ── Arcos de foco ─────────────────────────────────────────────────────
    HudRing {
      anchors.centerIn: parent
      radio: root.radio
      color: root.acento
      grosor: 2.5
      apertura: 42
      rotation: root.madreElegida ? root.anguloDe(root.madreElegida) : 0
      opacity: root.madreElegida ? 1 : 0
      Behavior on rotation { NumberAnimation { duration: root.msMedio; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: root.msRapido } }
    }

    HudRing {
      anchors.centerIn: parent
      radio: root.radioHijo
      color: root.acento
      grosor: 2
      apertura: 28
      rotation: root.anguloHijoElegido()
      opacity: root.hijoElegido ? 1 : 0
      Behavior on rotation { NumberAnimation { duration: root.msMedio; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: root.msRapido } }
    }

    // ── Radios hacia cada opción ──────────────────────────────────────────
    Repeater {
      model: root.menu

      delegate: Item {
        required property var modelData

        readonly property bool activa: root.sel === modelData.id

        x: panel.width / 2
        y: panel.height / 2
        width: Math.max(0, root.radio - root.lado * 0.42)
        height: 2
        transformOrigin: Item.Left
        rotation: root.anguloDe(modelData) - 90

        Rectangle {
          anchors.fill: parent
          radius: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Util.alpha(root.tinta, 0.02) }
            GradientStop { position: 1.0; color: Util.alpha(root.tinta, 0.13) }
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: 1
          opacity: activa ? 1 : 0
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Util.alpha(root.acento, 0.0) }
            GradientStop { position: 1.0; color: Util.alpha(root.acento, 0.9) }
          }
          Behavior on opacity { NumberAnimation { duration: root.msRapido } }
        }
      }
    }

    // Radios cortos de la opción elegida a sus hijos.
    Repeater {
      model: root.madreElegida !== null && root.madreElegida.hijos ? root.madreElegida.hijos : []

      delegate: Item {
        required property var modelData
        required property int index

        readonly property var angulos: root.angulosHijos(root.madreElegida)
        readonly property real ang: angulos[index] || 0
        readonly property real desde: root.radio * 1.02
        readonly property real hasta: root.radioHijo - root.ladoHijo * 0.42

        x: root.posX(ang, desde)
        y: root.posY(ang, desde)
        width: Math.max(0, hasta - desde)
        height: 1.5
        transformOrigin: Item.Left
        rotation: ang - 90

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: root.hijo === modelData.id
            ? Util.alpha(root.acento, 0.75)
            : Util.alpha(root.tinta, 0.10)
          Behavior on color { ColorAnimation { duration: root.msRapido } }
        }
      }
    }

    // ── Opciones ──────────────────────────────────────────────────────────
    Repeater {
      model: root.menu

      delegate: RadialNode {
        required property var modelData

        item: modelData
        elegida: root.sel === modelData.id
        atenuada: root.sel !== "" && !elegida
        lado: root.lado
        fuenteIcono: root.fuenteIcono
        fuenteTexto: root.fuenteTexto
        familia: root.fontFamily
        acento: root.acento
        tinta: root.tinta
        fondo: root.fondo

        x: root.posX(root.anguloDe(modelData), root.radio) - width / 2
        y: root.posY(root.anguloDe(modelData), root.radio) - height / 2
        Behavior on x { SpringAnimation { spring: 4; damping: 0.55 } }
        Behavior on y { SpringAnimation { spring: 4; damping: 0.55 } }
      }
    }

    Repeater {
      model: root.madreElegida !== null && root.madreElegida.hijos ? root.madreElegida.hijos : []

      delegate: RadialNode {
        required property var modelData
        required property int index

        readonly property var angulos: root.angulosHijos(root.madreElegida)
        readonly property real ang: angulos[index] || 0

        item: modelData
        elegida: root.hijo === modelData.id
        atenuada: root.hijo !== "" && !elegida
        hijo: true
        lado: root.ladoHijo
        fuenteIcono: root.fuenteIcono * 0.78
        fuenteTexto: root.fuenteTexto * 0.86
        familia: root.fontFamily
        acento: root.acento
        tinta: root.tinta
        fondo: root.fondo

        x: root.posX(ang, root.radioHijo) - width / 2
        y: root.posY(ang, root.radioHijo) - height / 2
        Behavior on x { SpringAnimation { spring: 4; damping: 0.55 } }
        Behavior on y { SpringAnimation { spring: 4; damping: 0.55 } }
      }
    }

    // ── Núcleo ────────────────────────────────────────────────────────────
    Item {
      id: nucleo
      anchors.centerIn: parent
      width: root.radio * 0.30
      height: width

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Util.alpha(root.acento, 0.10)
      }

      HudRing {
        anchors.centerIn: parent
        radio: root.radio * 0.15
        color: Util.alpha(root.acento, 0.55)
        grosor: 1.5
      }

      Rectangle {
        anchors.centerIn: parent
        width: root.radio * 0.34
        height: 1
        color: Util.alpha(root.tinta, 0.16)
      }

      Rectangle {
        anchors.centerIn: parent
        width: 1
        height: root.radio * 0.34
        color: Util.alpha(root.tinta, 0.16)
      }

      Rectangle {
        anchors.centerIn: parent
        width: root.lado * 0.075
        height: width
        radius: width / 2
        color: root.acento
      }

      Rectangle {
        id: ondaNucleo
        anchors.centerIn: parent
        width: nucleo.width
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.acento
        opacity: 0
        scale: 1

        NumberAnimation { id: ondaNucleoCrece; target: ondaNucleo; property: "scale"; from: 1; to: 1.9; duration: 420; easing.type: Easing.OutCubic }
        NumberAnimation { id: ondaNucleoFade; target: ondaNucleo; property: "opacity"; from: 0.55; to: 0; duration: 420; easing.type: Easing.OutCubic }
      }
    }

    SequentialAnimation {
      id: pulso
      NumberAnimation { target: nucleo; property: "scale"; from: 1; to: 1.12; duration: 110; easing.type: Easing.OutQuad }
      NumberAnimation { target: nucleo; property: "scale"; from: 1.12; to: 1; duration: 190; easing.type: Easing.OutCubic }
    }

    // Latido + chispa en cada cambio de selección. Solo con el menú ya
    // asentado: al abrir, todo aparece quieto.
    Connections {
      target: root
      function onSelChanged() { root.animarCambio() }
      function onHijoChanged() { root.animarCambio() }
    }

    // ── Chispa: viaja del centro a la opción ──────────────────────────────
    Item {
      id: chispa

      readonly property real angulo: root.hijoElegido
        ? root.anguloHijoElegido()
        : (root.madreElegida ? root.anguloDe(root.madreElegida) : 0)
      readonly property real destino: root.hijoElegido
        ? root.radioHijo - root.ladoHijo * 0.34
        : root.radio - root.lado * 0.34

      property real avance: 1

      visible: root.sel !== ""
      width: root.lado * 0.10
      height: width

      x: root.posX(angulo, root.radio * 0.16 + (destino - root.radio * 0.16) * avance) - width / 2
      y: root.posY(angulo, root.radio * 0.16 + (destino - root.radio * 0.16) * avance) - height / 2

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.acento
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: -width * 1.15
        radius: width / 2
        color: Util.alpha(root.acento, 0.16)
      }

      NumberAnimation {
        id: viaje
        target: chispa
        property: "avance"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.OutCubic
      }
    }

    // ── Encabezado HUD ────────────────────────────────────────────────────
    Row {
      id: encabezado
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(56)
      spacing: Style.space(10)

      Rectangle {
        width: Style.space(28)
        height: 1
        y: (rotulo.height - height) / 2
        color: Util.alpha(root.acento, 0.55)
      }

      Text {
        id: rotulo
        text: "HYPR · MENÚ RADIAL"
        color: Util.alpha(root.tinta, 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2.4
      }

      Rectangle {
        width: Style.space(28)
        height: 1
        y: (rotulo.height - height) / 2
        color: Util.alpha(root.acento, 0.55)
      }
    }

    // ── Globo con la selección ────────────────────────────────────────────
    Rectangle {
      visible: root.globo !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - Style.space(86)
      width: textoGlobo.implicitWidth + Style.space(64)
      height: Style.space(48)
      radius: height / 2
      color: Util.alpha(root.fondo, 0.94)
      border.width: 1
      border.color: Util.alpha(root.acento, 0.55)

      Rectangle {
        x: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height * 0.40
        radius: 1.5
        color: root.acento
      }

      Text {
        id: textoGlobo
        anchors.centerIn: parent
        text: root.globo
        color: root.tinta
        font.family: root.fontFamily
        font.pixelSize: root.fuenteGlobo
        font.letterSpacing: 0.8
      }
    }

    Text {
      visible: root.globo === ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - Style.space(86)
      text: "RECORRÉ CON EL DEDO"
      color: Util.alpha(root.tinta, 0.42)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 3
    }
  }
}
