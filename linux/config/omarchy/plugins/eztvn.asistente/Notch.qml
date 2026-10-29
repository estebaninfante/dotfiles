import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Notch del asistente de voz: una píldora negra que baja de la barra (como el
// Notch OSD) con un muñeco geométrico que cambia según lo que hace el
// asistente. El proceso de ~/developing/asistente lo maneja por IPC:
//   omarchy-shell asistente estado '{"estado":"escuchando","texto":"","tareas":0,"ahorro":false}'
// Estados: dormido, escuchando, pensando, hablando, haciendo, error.
// Las animaciones sólo corren mientras el notch está a la vista y nunca en
// ahorro extremo (`ahorro: true`), para no gastar batería.
//
// Tareas delegadas: lee ~/.local/state/asistente/tareas.json (inotify, sin
// sondeo). Mientras haya tareas en curso o resultados sin mirar, queda una
// píldora compacta; un clic (o `omarchy-shell asistente tareas`) despliega la
// lista con su estado y resultado.
Item {
  id: root

  property string estado: "dormido"
  property string texto: ""
  property int tareas: 0
  property bool ahorro: false

  // ---------- tareas delegadas ----------
  readonly property string archivoTareas: Quickshell.env("HOME") + "/.local/state/asistente/tareas.json"
  property var lista: []
  property int vistas: -1          // mayor # de tarea terminada que ya miraste
  property bool abierto: false
  property int abiertaN: -1        // tarea con el resultado desplegado
  property real ahora: Date.now() / 1000
  readonly property int activas: {
    var c = 0
    for (var i = 0; i < lista.length; i++) if (lista[i].estado === "en cola" || lista[i].estado === "corriendo") c++
    return Math.max(c, root.tareas)
  }
  readonly property int nuevas: {
    var c = 0
    for (var i = 0; i < lista.length; i++) if ((lista[i].estado === "lista" || lista[i].estado === "error") && lista[i].n > vistas) c++
    return c
  }
  readonly property string resumen: {
    var partes = []
    if (activas > 0) partes.push(activas + (activas === 1 ? " tarea en curso" : " tareas en curso"))
    if (nuevas > 0) partes.push(nuevas + (nuevas === 1 ? " lista ✓" : " listas ✓"))
    return partes.join(" · ")
  }

  function cargarTareas(texto) {
    try {
      var d = JSON.parse(texto || "{}")
      var t = (d.tareas || []).slice().reverse()   // más recientes arriba
      if (root.vistas < 0) {                        // al arrancar, lo viejo ya cuenta como visto
        var m = 0
        for (var i = 0; i < t.length; i++) if (t[i].estado === "lista" || t[i].estado === "error") m = Math.max(m, t[i].n)
        root.vistas = m
      }
      root.lista = t
    } catch (e) {}
    root.actualizarReveal()
  }

  function marcarVistas() {
    var m = root.vistas
    for (var i = 0; i < lista.length; i++) if (lista[i].estado === "lista" || lista[i].estado === "error") m = Math.max(m, lista[i].n)
    root.vistas = m
  }

  function alternarLista() {
    root.abierto = !root.abierto
    if (root.abierto) { root.marcarVistas(); root.ahora = Date.now() / 1000; cierre.restart() }
    root.actualizarReveal()
    return root.abierto ? "abierta" : "cerrada"
  }

  function actualizarReveal() {
    root.reveal = (root.activo || root.activas > 0 || root.nuevas > 0 || root.abierto) ? 1 : 0
  }

  function hace(seg) {
    seg = Math.max(0, Math.round(seg))
    if (seg < 60) return seg + " s"
    if (seg < 3600) return Math.round(seg / 60) + " min"
    return Math.round(seg / 3600) + " h"
  }

  FileView {
    path: root.archivoTareas
    watchChanges: true
    printErrors: false
    onLoaded: root.cargarTareas(text())
    onFileChanged: reload()
  }

  Timer { id: reloj; interval: 1000; repeat: true; running: root.abierto; onTriggered: root.ahora = Date.now() / 1000 }
  Timer { id: cierre; interval: 45000; onTriggered: { root.abierto = false; root.actualizarReveal() } }

  readonly property bool activo: estado !== "dormido"
  readonly property bool compacto: !activo
  readonly property bool animar: panel.visible && !root.ahorro

  // ---------- geometría (misma familia que el Notch OSD) ----------
  readonly property int topMargin: Style.space(30)
  readonly property int alto: compacto ? Style.space(34) : Style.space(50)
  readonly property int pad: compacto ? Style.space(8) : Style.space(10)
  readonly property int gap: Style.space(12)
  readonly property int lado: alto - pad * 2          // tamaño del muñeco
  readonly property int maxTexto: Style.space(380)

  readonly property string etiqueta: {
    if (root.texto !== "") return root.texto
    switch (root.estado) {
      case "escuchando": return "Te escucho…"
      case "pensando": return "Pensando…"
      case "haciendo": return "En eso…"
      case "error": return "Algo falló"
      default: return ""
    }
  }
  readonly property bool conTexto: !compacto && etiqueta !== ""
  readonly property int anchoTexto: conTexto ? Math.min(Math.ceil(medida.advanceWidth), maxTexto) : 0
  readonly property int anchoTareas: compacto && resumen !== "" ? Math.ceil(medidaTareas.advanceWidth) + gap : 0
  readonly property int anchoTotal: pad * 2 + lado + (conTexto ? gap + anchoTexto : 0) + anchoTareas + (compacto ? 0 : Style.space(6))

  property real reveal: 0
  readonly property real eased: Math.max(0, Math.min(1.05, reveal))
  readonly property int anchoCard: Math.round(anchoTotal * (0.45 + 0.55 * eased))
  readonly property int altoCard: Math.max(0, Math.round(alto * eased))

  Behavior on reveal { SpringAnimation { spring: 20; damping: 0.58; mass: 1; epsilon: 0.0005 } }

  // ---------- color por estado ----------
  readonly property color tinte: {
    switch (root.estado) {
      case "escuchando": return "#5ee7ff"
      case "pensando": return "#b28cff"
      case "hablando": return "#7dffb3"
      case "haciendo": return "#ffd166"
      case "error": return "#ff7a7a"
      default: return "#a9b4c6"
    }
  }
  property color cuerpo: tinte
  Behavior on cuerpo { ColorAnimation { duration: 260 } }

  function aplicar(json) {
    try {
      var p = JSON.parse(json || "{}")
      root.estado = p.estado || "dormido"
      root.texto = (p.texto || "").replace(/\s+/g, " ").trim()
      root.tareas = p.tareas || 0
      root.ahorro = !!p.ahorro
    } catch (e) {
      return "json inválido"
    }
    root.actualizarReveal()
    vigia.restart()
    return "ok"
  }

  // Si el asistente muere sin despedirse, el notch no se queda pegado.
  Timer {
    id: vigia
    interval: 180000
    onTriggered: { if (root.activo) root.aplicar('{"estado":"dormido","tareas":' + root.tareas + '}') }
  }

  TextMetrics { id: medida; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; text: root.etiqueta }
  TextMetrics { id: medidaTareas; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true; text: root.resumen }

  IpcHandler {
    target: "asistente"
    function estado(json: string): string { return root.aplicar(json) }
    function ocultar(): string { return root.aplicar('{"estado":"dormido"}') }
    function tareas(): string { return root.alternarLista() }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    id: panel
    visible: root.reveal > 0.003
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "asistente-notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // sólo la píldora y la lista reciben clics; el resto de la pantalla pasa de largo
    mask: Region {
      item: notch
      Region { item: listaCard }
    }

    Item {
      id: notch
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: root.topMargin
      width: root.anchoCard
      height: root.altoCard
      clip: true

      Behavior on width { enabled: root.reveal > 0.98; SpringAnimation { spring: 18; damping: 0.7; epsilon: 0.3 } }

      Rectangle {
        anchors.fill: parent
        radius: Math.min(root.alto / 2, height / 2)
        color: "#000000"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
      }

      Row {
        x: root.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap
        opacity: Math.max(0, Math.min(1, (root.eased - 0.15) / 0.8))

        // ---------------- el muñeco ----------------
        Item {
          id: muneco
          width: root.lado
          height: root.lado
          anchors.verticalCenter: parent.verticalCenter

          property real s: root.lado
          property real parpado: 1
          property real boca: s * 0.06
          property real salto: 0

          readonly property real ojoAlto: {
            switch (root.estado) {
              case "escuchando": return s * 0.32
              case "pensando": return s * 0.16
              case "haciendo": return s * 0.07
              case "hablando": return s * 0.24
              case "error": return s * 0.12
              default: return s * 0.07
            }
          }
          readonly property real miradaX: root.estado === "pensando" ? s * 0.07 : (root.estado === "dormido" ? s * 0.05 : 0)
          readonly property real miradaY: root.estado === "pensando" ? -s * 0.09 : 0

          // anillo de escucha: ondas que salen del muñeco
          Rectangle {
            id: onda
            anchors.centerIn: cuerpoMuneco
            width: muneco.s; height: muneco.s
            radius: width * 0.34
            color: "transparent"
            border.width: 2
            border.color: root.cuerpo
            visible: root.estado === "escuchando" && root.animar
            opacity: 0
            ParallelAnimation {
              running: onda.visible
              loops: Animation.Infinite
              NumberAnimation { target: onda; property: "scale"; from: 0.9; to: 1.55; duration: 1100; easing.type: Easing.OutCubic }
              NumberAnimation { target: onda; property: "opacity"; from: 0.7; to: 0; duration: 1100; easing.type: Easing.OutCubic }
            }
          }

          // órbita de "pensando": tres puntos girando alrededor
          Item {
            id: orbita
            anchors.centerIn: cuerpoMuneco
            width: muneco.s * 1.22; height: width
            visible: root.estado === "pensando"
            Repeater {
              model: 3
              Rectangle {
                width: muneco.s * 0.11; height: width; radius: width / 2
                color: root.cuerpo
                opacity: 0.55 + index * 0.2
                x: orbita.width / 2 + Math.cos(index * 2.094) * orbita.width / 2 - width / 2
                y: orbita.height / 2 + Math.sin(index * 2.094) * orbita.height / 2 - height / 2
              }
            }
            RotationAnimation on rotation {
              running: orbita.visible && root.animar
              from: 0; to: 360; duration: 1400; loops: Animation.Infinite
            }
          }

          Rectangle {
            id: cuerpoMuneco
            width: muneco.s; height: muneco.s
            y: muneco.salto
            radius: width * 0.34
            gradient: Gradient {
              GradientStop { position: 0.0; color: Qt.lighter(root.cuerpo, 1.25) }
              GradientStop { position: 1.0; color: Qt.darker(root.cuerpo, 1.45) }
            }
            rotation: root.estado === "pensando" ? -6 : 0
            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

            // brillo
            Rectangle {
              x: parent.width * 0.16; y: parent.height * 0.12
              width: parent.width * 0.22; height: parent.height * 0.12
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.35)
            }

            // ojos
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: muneco.miradaX
              y: parent.height * (root.estado === "hablando" ? 0.30 : 0.40) - height / 2 + muneco.miradaY
              spacing: muneco.s * 0.17
              Behavior on y { NumberAnimation { duration: 180 } }
              Repeater {
                model: 2
                Rectangle {
                  width: muneco.s * 0.15
                  height: Math.max(2, muneco.ojoAlto * muneco.parpado)
                  radius: width / 2
                  color: "#0b0d12"
                  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                  Behavior on height { NumberAnimation { duration: 120 } }
                }
              }
            }

            // boca (sólo al hablar)
            Rectangle {
              visible: root.estado === "hablando"
              anchors.horizontalCenter: parent.horizontalCenter
              y: parent.height * 0.62
              width: muneco.s * 0.30
              height: muneco.boca
              radius: Math.min(width, height) / 2
              color: "#0b0d12"
              Behavior on height { NumberAnimation { duration: 90 } }
            }
          }

          // parpadeo
          SequentialAnimation {
            running: root.animar && root.estado !== "dormido" && root.estado !== "haciendo"
            loops: Animation.Infinite
            PauseAnimation { duration: 2600 }
            NumberAnimation { target: muneco; property: "parpado"; to: 0.08; duration: 70 }
            NumberAnimation { target: muneco; property: "parpado"; to: 1; duration: 110 }
          }

          // boca que sigue la voz
          Timer {
            interval: 110
            repeat: true
            running: root.animar && root.estado === "hablando"
            onTriggered: muneco.boca = muneco.s * (0.05 + Math.random() * 0.17)
            onRunningChanged: if (!running) muneco.boca = muneco.s * 0.06
          }

          // saltito al hablar o hacer algo
          SequentialAnimation {
            running: root.animar && (root.estado === "hablando" || root.estado === "haciendo")
            loops: Animation.Infinite
            NumberAnimation { target: muneco; property: "salto"; to: -muneco.s * 0.06; duration: 240; easing.type: Easing.OutQuad }
            NumberAnimation { target: muneco; property: "salto"; to: 0; duration: 260; easing.type: Easing.InQuad }
            onRunningChanged: if (!running) muneco.salto = 0
          }
        }

        Text {
          visible: root.conTexto
          width: root.anchoTexto
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.etiqueta
          font: medida.font
          color: root.estado === "escuchando" && root.texto === "" ? Qt.rgba(1, 1, 1, 0.6) : "#ffffff"
          elide: Text.ElideLeft
          maximumLineCount: 1
        }

        // tareas delegadas (modo compacto)
        Text {
          visible: root.compacto && root.resumen !== ""
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.resumen
          font: medidaTareas.font
          color: root.nuevas > 0 ? "#7dffb3" : Qt.rgba(1, 1, 1, 0.75)
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.alternarLista()
      }
    }

    // ---------------- lista de tareas ----------------
    Rectangle {
      id: listaCard
      visible: root.abierto
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: notch.bottom
      anchors.topMargin: Style.space(8)
      width: Style.space(460)
      height: visible ? columna.implicitHeight + Style.space(24) : 0
      radius: Style.space(18)
      color: "#000000"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.08)

      MouseArea { anchors.fill: parent; onClicked: cierre.restart() }

      Column {
        id: columna
        x: Style.space(14); y: Style.space(12)
        width: parent.width - Style.space(28)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: root.lista.length === 0 ? "Sin tareas delegadas todavía" : "Tareas delegadas · un solo hilo de Hermes por día"
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: Qt.rgba(1, 1, 1, 0.5)
        }

        Repeater {
          model: root.lista.slice(0, 8)
          delegate: Item {
            required property var modelData
            readonly property var t: modelData
            readonly property bool desplegada: root.abiertaN === t.n
            width: columna.width
            height: fila.implicitHeight

            Column {
              id: fila
              width: parent.width
              spacing: Style.space(3)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  id: icono
                  textFormat: Text.PlainText
                  text: t.estado === "en cola" ? "◷" : t.estado === "corriendo" ? "◐" : t.estado === "lista" ? "✓" : "✕"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: t.estado === "lista" ? "#7dffb3" : t.estado === "error" ? "#ff7a7a" : t.estado === "corriendo" ? "#b28cff" : Qt.rgba(1, 1, 1, 0.5)
                  RotationAnimation on rotation {
                    running: t.estado === "corriendo" && root.abierto && !root.ahorro
                    from: 0; to: 360; duration: 1200; loops: Animation.Infinite
                  }
                }
                Text {
                  width: parent.width - icono.width - tiempo.width - Style.space(16)
                  textFormat: Text.PlainText
                  text: "#" + t.n + "  " + t.tarea
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: "#ffffff"
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }
                Text {
                  id: tiempo
                  textFormat: Text.PlainText
                  text: t.estado === "en cola" ? "en cola"
                      : t.estado === "corriendo" ? root.hace(root.ahora - t.inicio)
                      : "hace " + root.hace(root.ahora - (t.fin || t.creada))
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  color: Qt.rgba(1, 1, 1, 0.5)
                }
              }

              Text {
                visible: t.resultado !== ""
                x: icono.width + Style.space(8)
                width: parent.width - x
                textFormat: Text.PlainText
                text: t.resultado
                wrapMode: Text.Wrap
                maximumLineCount: desplegada ? 40 : 2
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: t.estado === "error" ? "#ffb3b3" : Qt.rgba(1, 1, 1, 0.72)
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.abiertaN = desplegada ? -1 : t.n; cierre.restart() }
            }
          }
        }
      }
    }
  }
}
