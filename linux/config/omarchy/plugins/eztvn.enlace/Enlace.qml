import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "motion"

// Transiciones de "enlace" entre equipos.
//
// Moonlight/Sunshine: al conectar un cliente, sunshine-vd.sh crea la pantalla
// virtual, cambia de modo o apaga el panel. Sin nada encima eso es un parpadeo
// seco y un salto de resolución. Acá se tapa con una escena (la pantalla del
// equipo y la del cliente separándose), el guion hace los cambios mientras la
// escena está opaca, y después pide `streamReveal`: la escena se abre ya sobre
// la disposición nueva (y el cliente ve esa apertura en su stream, porque la
// capa también se dibuja en SUNSHINE-VD). Al desconectar, lo mismo al revés.
//
// lan-mouse: no tapa nada (sin entrada, sin foco). Al conectarse el peer se
// muestran las dos pantallas encajándose por el borde compartido y después ese
// borde brilla en la pantalla real. Cada cruce del puntero marca el punto del
// borde por donde pasó. Los eventos salen del journal del servicio: el socket
// de lan-mouse habla bincode y el CLI no avisa, así que es lo único que llega
// sin polling.
//
// No decide los tiempos del stream: el guion llama streamIn/streamOut, corre
// los cambios y pide el reveal. Si el guion muere, la red de seguridad abre.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")

  // ------------------------------------------------------------------ stream
  // "in" = se conecta un cliente, "out" = vuelve el escritorio.
  property string streamKind: "in"
  property var streamInfo: ({})
  // 0 descubierto, 1 escena opaca.
  property real veil: 0
  // 0 = una sola pantalla (la del equipo), 1 = equipo y cliente separados.
  property real streamMorph: 0
  // Desplazamiento continuo de los pulsos del haz (0..1, en loop).
  property real flow: 0
  // Al abrir, el contenido se agranda apenas mientras se desvanece.
  property real revealLift: 0

  // ------------------------------------------------------------------ lan-mouse
  property real linkScrim: 0
  property real linkCard: 0
  property real linkJoin: 0
  property real linkEdge: 0
  property real edgeGlow: 0
  property color edgeColor: Color.accent
  property string edgeLabel: ""
  property real crossGlow: 0
  // Coordenada global del cruce (x o y según el borde); -1 = centro del borde.
  property real crossX: -1
  property real crossY: -1

  property string peerPosition: "right"
  property string peerName: "peer"
  property string localName: "este equipo"
  property bool linked: false
  // true mientras el puntero está del lado del peer (salimos y no ha vuelto).
  property bool sentPointer: false
  property double lastLinkUp: 0
  property double lastLinkDown: 0
  property double lastCrossOut: 0
  property double lastCrossIn: 0
  property bool paused: false

  readonly property bool streamActive: veil > 0.001 || streamInAnim.running || streamOutAnim.running
  readonly property bool linkActive: linkScrim > 0.001 || linkCard > 0.001 || edgeGlow > 0.001
    || crossGlow > 0.001 || linkUpAnim.running || linkDownAnim.running || crossAnim.running
  readonly property bool active: streamActive || linkActive

  readonly property bool horizontalEdge: peerPosition === "left" || peerPosition === "right"
  readonly property string positionText: ({
    left: "izquierdo", right: "derecho", top: "superior", bottom: "inferior"
  })[peerPosition] || peerPosition

  // La pantalla que tiene el borde por donde se cruza (la más extrema en la
  // dirección del peer). Con un solo monitor es esa, siempre.
  readonly property string edgeScreen: {
    var screens = Quickshell.screens
    var best = null
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      if (String(s.name).indexOf("SUNSHINE") === 0 || String(s.name).indexOf("HEADLESS") === 0) continue
      if (!best) { best = s; continue }
      if (peerPosition === "right" && s.x + s.width > best.x + best.width) best = s
      else if (peerPosition === "left" && s.x < best.x) best = s
      else if (peerPosition === "bottom" && s.y + s.height > best.y + best.height) best = s
      else if (peerPosition === "top" && s.y < best.y) best = s
    }
    return best ? String(best.name) : ""
  }

  function parse(json) {
    try { return JSON.parse(String(json || "{}")) || {} } catch (e) { return {} }
  }

  function info(key, fallback) {
    var v = streamInfo ? streamInfo[key] : undefined
    return (v === undefined || v === null || v === "") ? fallback : v
  }

  // ------------------------------------------------------------------ stream API
  function streamIn(json) {
    streamInfo = parse(json)
    streamKind = "in"
    revealAnim.stop(); streamOutAnim.stop()
    revealLift = 0
    streamMorph = 0
    safety.restart()
    streamInAnim.restart()
  }

  function streamOut(json) {
    var extra = parse(json)
    // Conserva lo que se sabía de la sesión (resolución, modo) para la escena.
    var merged = Object.assign({}, streamInfo || {}, extra)
    streamInfo = merged
    streamKind = "out"
    revealAnim.stop(); streamInAnim.stop()
    revealLift = 0
    streamMorph = 1
    safety.restart()
    streamOutAnim.restart()
  }

  function streamReveal(ms) {
    var d = parseInt(String(ms), 10)
    revealDelay.interval = (isFinite(d) && d > 0) ? Math.min(d, 5000) : 1
    revealDelay.restart()
  }

  function doReveal() {
    safety.stop()
    streamInAnim.stop(); streamOutAnim.stop()
    if (streamKind === "in") streamMorph = 1
    else streamMorph = 0
    revealAnim.restart()
  }

  // ------------------------------------------------------------------ lan-mouse API
  function linkUp() {
    if (Tokens.reduced) return
    linkDownAnim.stop(); crossAnim.stop()
    edgeColor = Color.accent
    edgeLabel = ""
    linkUpAnim.restart()
  }

  function linkDown() {
    if (Tokens.reduced) return
    if (linkUpAnim.running) return
    edgeColor = Color.muted
    edgeLabel = "lan-mouse · " + peerName + " desconectado"
    linkDownAnim.restart()
  }

  function cross(dir) {
    if (Tokens.reduced || linkUpAnim.running) return
    cursorProc.running = false
    cursorProc.running = true
  }

  function onLog(line) {
    if (paused) return
    var s = String(line)
    var now = Date.now()
    // "acknowledged" es la confirmación real de que el peer aceptó: el
    // título/captura pueden existir sin conexión. Se repite por cada Enter,
    // así que sólo anima al pasar de desconectado a conectado.
    if (/acknowledged the connection!|dtls client connected/.test(s)) {
      if (!linked) {
        linked = true
        if (now - lastLinkUp > 15000) { lastLinkUp = now; linkUp() }
      }
    } else if (/entering client/.test(s)) {
      // El puntero salió de este equipo hacia el peer. Sólo ocurre con la
      // captura armada; los intentos fallidos loguean "no active client".
      sentPointer = true
      if (now - lastCrossOut > 700) { lastCrossOut = now; cross("out") }
    } else if (/entered this device/.test(s)) {
      // El puntero llegó desde el peer a esta máquina.
      linked = true
      sentPointer = false
      if (now - lastCrossIn > 700) { lastCrossIn = now; cross("in") }
    } else if (/left remote client device region/.test(s)) {
      // El peer soltó la captura: el puntero volvió. Un Leave espurio (enlace
      // caído, intento abortado) llega igual; si no habíamos salido, no anima.
      if (sentPointer) {
        sentPointer = false
        if (now - lastCrossIn > 700) { lastCrossIn = now; cross("in") }
      }
    } else if (/connection closed|active connections: \[\]|deactivated client|compositor released mouse|no active client at this position/.test(s)) {
      // Enlace caído o captura desactivada. "no active client at this
      // position" es el borde tocado con el cliente apagado: avisar una vez,
      // no fingir un cruce.
      if (linked || sentPointer) { linked = false; sentPointer = false }
      if (now - lastLinkDown > 15000) { lastLinkDown = now; linkDown() }
    }
  }

  // ------------------------------------------------------------------ animaciones: stream
  SequentialAnimation {
    id: streamInAnim
    ParallelAnimation {
      NumberAnimation { target: root; property: "veil"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
      SequentialAnimation {
        PauseAnimation { duration: Tokens.fast }
        NumberAnimation { target: root; property: "streamMorph"; from: 0; to: 1; duration: Tokens.draw; easing.type: Tokens.move }
      }
    }
  }

  SequentialAnimation {
    id: streamOutAnim
    ParallelAnimation {
      NumberAnimation { target: root; property: "veil"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
      SequentialAnimation {
        PauseAnimation { duration: Tokens.fast }
        NumberAnimation { target: root; property: "streamMorph"; from: 1; to: 0; duration: Tokens.draw; easing.type: Tokens.move }
      }
    }
  }

  SequentialAnimation {
    id: revealAnim
    ParallelAnimation {
      NumberAnimation { target: root; property: "revealLift"; from: 0; to: 1; duration: Tokens.slow + Tokens.base; easing.type: Tokens.standard }
      SequentialAnimation {
        PauseAnimation { duration: Tokens.fast }
        NumberAnimation { target: root; property: "veil"; to: 0; duration: Tokens.slow + Tokens.fast; easing.type: Tokens.standard }
      }
    }
    ScriptAction { script: root.revealLift = 0 }
  }

  NumberAnimation on flow {
    from: 0; to: 1
    duration: 1400
    loops: Animation.Infinite
    running: (root.veil > 0.001 || root.linkCard > 0.001) && !Tokens.reduced
  }

  Timer { id: revealDelay; repeat: false; onTriggered: root.doReveal() }

  // Si el guion murió con la escena puesta, no dejar la pantalla tapada.
  Timer { id: safety; interval: 15000; repeat: false; onTriggered: root.doReveal() }

  // ------------------------------------------------------------------ animaciones: lan-mouse
  SequentialAnimation {
    id: linkUpAnim
    ScriptAction {
      script: {
        root.linkScrim = 0; root.linkCard = 0; root.linkJoin = 0
        root.linkEdge = 0; root.edgeGlow = 0; root.crossGlow = 0
      }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "linkScrim"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
      NumberAnimation { target: root; property: "linkCard"; to: 1; duration: Tokens.slow; easing.type: Tokens.enter }
    }
    NumberAnimation { target: root; property: "linkJoin"; to: 1; duration: Tokens.morph * 2; easing.type: Tokens.spring }
    NumberAnimation { target: root; property: "linkEdge"; to: 1; duration: Tokens.draw; easing.type: Tokens.drawCurve }
    PauseAnimation { duration: 1200 }
    ParallelAnimation {
      NumberAnimation { target: root; property: "linkCard"; to: 0; duration: Tokens.morph; easing.type: Tokens.exit }
      NumberAnimation { target: root; property: "linkScrim"; to: 0; duration: Tokens.slow; easing.type: Tokens.exit }
      NumberAnimation { target: root; property: "edgeGlow"; to: 1; duration: Tokens.morph; easing.type: Tokens.enter }
    }
    PauseAnimation { duration: 900 }
    NumberAnimation { target: root; property: "edgeGlow"; to: 0; duration: 900; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: linkDownAnim
    NumberAnimation { target: root; property: "edgeGlow"; to: 0.8; duration: Tokens.base; easing.type: Tokens.enter }
    PauseAnimation { duration: 1100 }
    NumberAnimation { target: root; property: "edgeGlow"; to: 0; duration: 700; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: crossAnim
    NumberAnimation { target: root; property: "crossGlow"; to: 1; duration: Tokens.fast; easing.type: Tokens.enter }
    PauseAnimation { duration: 160 }
    NumberAnimation { target: root; property: "crossGlow"; to: 0; duration: 650; easing.type: Easing.OutCubic }
  }

  // ------------------------------------------------------------------ fuentes
  Process {
    id: journal
    command: ["journalctl", "--user", "-u", "lan-mouse.service", "-f", "-n", "0", "-o", "cat", "-q"]
    running: !root.paused
    stdout: SplitParser { onRead: data => root.onLog(data) }
    stderr: StdioCollector {}
    onExited: if (!root.paused) journalRetry.restart()
  }
  Timer { id: journalRetry; interval: 5000; onTriggered: journal.running = !root.paused }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = root.parse(text)
        root.crossX = isFinite(Number(p.x)) ? Number(p.x) : -1
        root.crossY = isFinite(Number(p.y)) ? Number(p.y) : -1
        root.edgeColor = Color.accent
        crossAnim.restart()
      }
    }
  }

  FileView {
    path: root.home + "/.config/lan-mouse/config.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = text()
      var pos = /position\s*=\s*"(\w+)"/.exec(t)
      if (pos) root.peerPosition = pos[1]
      var named = /^"[0-9a-f:]+"\s*=\s*"([^"]+)"/m.exec(t)
      var host = /hostname\s*=\s*"([^"]+)"/.exec(t)
      root.peerName = named ? named[1] : (host ? host[1] : "peer")
    }
  }

  FileView {
    path: "/etc/hostname"
    printErrors: false
    onLoaded: { var h = text().trim(); if (h !== "") root.localName = h }
  }

  // Ahorro extremo: sin journal ni brillos. El velo del stream sigue (lo pide
  // un guion, no hace polling).
  FileView {
    path: root.home + "/.local/state/power-extreme/on"
    printErrors: false
    onLoaded: root.paused = true
  }

  IpcHandler {
    target: "eztvn.enlace"

    function streamIn(json: string): string { root.streamIn(json); return "ok" }
    function streamOut(json: string): string { root.streamOut(json); return "ok" }
    function streamReveal(ms: string): string { root.streamReveal(ms); return "ok" }
    function linkUp(): string { root.linkUp(); return "ok" }
    function linkDown(): string { root.linkDown(); return "ok" }
    function cross(): string { root.cross("out"); return "ok" }
    function pause(): string { root.paused = true; return "ok" }
    function resume(): string { root.paused = false; return "ok" }
    function phase(): string { return root.veil > 0.999 ? "covered" : (root.active ? "moving" : "open") }
    function ping(): string { return "ok" }
    function debug(): string {
      return JSON.stringify({ veil: root.veil, scrim: root.linkScrim, card: root.linkCard, edge: root.edgeGlow,
        cross: root.crossGlow, edgeScreen: root.edgeScreen, pos: root.peerPosition, bg: String(Color.background),
        accent: String(Color.accent), paused: root.paused })
    }
  }

  // ------------------------------------------------------------------ piezas
  // Una pantalla dibujada: marco con el acento, relleno tenue, etiqueta abajo.
  component ScreenTile: Item {
    id: tile
    property string label: ""
    property string caption: ""
    property real lit: 1
    property color tint: Color.accent

    Rectangle {
      anchors.fill: parent
      radius: Math.min(width, height) * 0.08
      color: Color.background
    }

    Rectangle {
      anchors.fill: parent
      radius: Math.min(width, height) * 0.08
      color: Qt.rgba(tile.tint.r, tile.tint.g, tile.tint.b, 0.06 + 0.10 * tile.lit)
      border.width: 2
      border.color: Qt.rgba(tile.tint.r, tile.tint.g, tile.tint.b, 0.25 + 0.65 * tile.lit)

      // Brillo interior arriba: sugiere vidrio sin dibujar un monitor literal.
      Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 2 }
        height: parent.height * 0.45
        radius: parent.radius
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.07 * tile.lit) }
          GradientStop { position: 1; color: "transparent" }
        }
      }

      Text {
        anchors.centerIn: parent
        text: tile.caption
        color: Color.foreground
        opacity: 0.55 + 0.4 * tile.lit
        font.family: Style.fontFamily
        font.pixelSize: Math.max(10, Math.min(parent.height * 0.16, 15))
      }
    }

    Text {
      anchors { top: parent.bottom; topMargin: 12; horizontalCenter: parent.horizontalCenter }
      text: tile.label
      color: Color.foreground
      opacity: 0.5 + 0.4 * tile.lit
      font.family: Style.fontFamily
      font.pixelSize: 13
      font.letterSpacing: 1.2
    }
  }

  // Escena del stream: cubre la pantalla completa.
  component StreamScene: Item {
    id: scene
    property var screenRef: null

    readonly property bool going: root.streamKind === "in"
    readonly property string mode: String(root.info("mode", "headless"))
    readonly property int cw: Number(root.info("width", 1920)) || 1920
    readonly property int ch: Number(root.info("height", 1080)) || 1080
    readonly property real hostAspect: screenRef && screenRef.height > 0 ? screenRef.width / screenRef.height : 1.6
    readonly property real m: root.streamMorph

    readonly property real unit: Math.min(width, height) / 900
    readonly property real hostW: 230 * unit
    readonly property real hostH: hostW / hostAspect
    readonly property real clientH: hostH
    readonly property real clientW: Math.min(clientH * (cw / ch), hostW * 1.4)
    readonly property real gap: mode === "extend" || mode === "extender" ? 0 : 70 * unit
    readonly property real span: hostW + gap + clientW

    opacity: root.veil

    Rectangle {
      anchors.fill: parent
      color: Color.background
    }
    // Un halo tenue del acento detrás de la composición.
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: scene.width / 2; centerY: scene.height / 2 - 50 * scene.unit
          focalX: centerX; focalY: centerY
          centerRadius: Math.max(scene.width, scene.height) * 0.45
          GradientStop { position: 0; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10) }
          GradientStop { position: 1; color: "transparent" }
        }
        startX: 0; startY: 0
        PathLine { x: scene.width; y: 0 }
        PathLine { x: scene.width; y: scene.height }
        PathLine { x: 0; y: scene.height }
        PathLine { x: 0; y: 0 }
      }
    }

    Item {
      id: stage
      anchors.centerIn: parent
      width: scene.span
      height: scene.hostH
      anchors.verticalCenterOffset: -50 * scene.unit
      scale: 1 + 0.05 * root.revealLift

      ScreenTile {
        id: hostTile
        width: scene.hostW
        height: scene.hostH
        x: (stage.width - width) / 2 - scene.m * ((stage.width - width) / 2)
        y: 0
        label: root.localName
        caption: scene.mode === "headless" || scene.mode === "off" ? (scene.m > 0.5 ? "apagada" : "") : ""
        // En "pantalla apagada" el equipo se atenúa a medida que se separan.
        lit: scene.mode === "headless" || scene.mode === "off" ? 1 - 0.75 * scene.m : 1
      }

      // Haz entre las dos: una línea que se llena y pulsos que viajan.
      Item {
        id: beam
        visible: scene.gap > 0
        x: hostTile.x + hostTile.width
        width: Math.max(0, clientTile.x - x)
        height: 2
        anchors.verticalCenter: hostTile.verticalCenter
        opacity: scene.m

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
        }
        Repeater {
          model: 3
          Rectangle {
            required property int index
            width: 6; height: 6; radius: 3
            color: Color.accent
            anchors.verticalCenter: parent.verticalCenter
            readonly property real p: (root.flow + index / 3) % 1
            x: (scene.going ? p : 1 - p) * (beam.width - width)
            opacity: Math.sin(p * Math.PI)
          }
        }
      }

      ScreenTile {
        id: clientTile
        width: scene.clientW
        height: scene.clientH
        x: (stage.width - width) / 2 + scene.m * ((stage.width - width) / 2)
        y: 0
        opacity: scene.m
        scale: 0.85 + 0.15 * scene.m
        label: "cliente"
        caption: scene.cw + "×" + scene.ch
        lit: 1
      }
    }

    Column {
      anchors { top: stage.bottom; topMargin: 70 * scene.unit; horizontalCenter: parent.horizontalCenter }
      spacing: 10 * scene.unit
      opacity: Math.min(1, root.veil * 1.4) * (1 - root.revealLift)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: scene.going ? "Moonlight" : "De vuelta en " + root.localName
        color: Color.foreground
        font.family: Style.fontFamily
        font.pixelSize: Math.round(34 * scene.unit)
        font.weight: Font.Light
        font.letterSpacing: 2
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: scene.going
          ? String(root.info("app", "Sesión de streaming"))
          : "Sesión de streaming terminada"
        color: Color.accent
        font.family: Style.fontFamily
        font.pixelSize: Math.round(16 * scene.unit)
        font.letterSpacing: 1
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          var bits = [scene.cw + "×" + scene.ch]
          var fps = Number(root.info("fps", 0))
          if (fps > 0) bits.push(fps + " Hz")
          var net = String(root.info("net", ""))
          if (net === "tailscale") bits.push("Tailscale")
          else if (net === "local") bits.push("LAN")
          if (!scene.going) return "Restaurando la pantalla"
          return bits.join("  ·  ")
        }
        color: Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Math.round(13 * scene.unit)
        font.letterSpacing: 1
      }
    }
  }

  // Escena de lan-mouse: dos pantallas que encajan por el borde compartido.
  component LinkCard: Item {
    id: card
    readonly property real unit: Math.min(width, height) / 900
    readonly property real tileW: 210 * unit
    readonly property real tileH: tileW / 1.6
    readonly property string pos: root.peerPosition
    readonly property real far: 160 * unit * (1 - root.linkJoin)
    // El peer se acerca desde su lado: dx/dy son su posición final.
    readonly property real dx: pos === "right" ? tileW : (pos === "left" ? -tileW : 0)
    readonly property real dy: pos === "bottom" ? tileH : (pos === "top" ? -tileH : 0)
    readonly property real fx: pos === "right" ? far : (pos === "left" ? -far : 0)
    readonly property real fy: pos === "bottom" ? far : (pos === "top" ? -far : 0)

    opacity: root.linkCard

    Item {
      id: pair
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -30 * card.unit
      // Centra el par completo, no solo la pantalla local.
      anchors.horizontalCenterOffset: -card.dx / 2
      width: card.tileW
      height: card.tileH
      scale: 0.94 + 0.06 * root.linkCard

      ScreenTile {
        anchors.fill: parent
        label: root.localName
      }

      ScreenTile {
        width: card.tileW
        height: card.tileH
        x: card.dx + card.fx
        y: card.dy + card.fy
        opacity: Math.min(1, root.linkJoin * 1.3)
        label: root.peerName
      }

      // El borde compartido: se traza desde el centro hacia los extremos, con
      // pulsos que lo cruzan de un lado al otro (la sincronización).
      Item {
        id: seam
        readonly property bool vertical: card.pos === "left" || card.pos === "right"
        width: vertical ? 4 : card.tileW * root.linkEdge
        height: vertical ? card.tileH * root.linkEdge : 4
        x: card.pos === "right" ? card.tileW - 2
          : card.pos === "left" ? -2
          : (card.tileW - width) / 2
        y: card.pos === "bottom" ? card.tileH - 2
          : card.pos === "top" ? -2
          : (card.tileH - height) / 2
        visible: root.linkEdge > 0

        Rectangle {
          anchors.centerIn: parent
          width: seam.vertical ? 26 : parent.width + 20
          height: seam.vertical ? parent.height + 20 : 26
          radius: 13
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
        }
        Rectangle {
          anchors.fill: parent
          radius: 2
          color: Color.accent
        }
        Repeater {
          model: 4
          Rectangle {
            required property int index
            readonly property real p: (root.flow + index / 4) % 1
            width: 8; height: 8; radius: 4
            color: Color.foreground
            opacity: Math.sin(p * Math.PI) * root.linkEdge
            x: seam.vertical
              ? (seam.width - width) / 2 + (index % 2 ? 1 : -1) * (p - 0.5) * 34
              : p * (seam.width - width)
            y: seam.vertical
              ? p * (seam.height - height)
              : (seam.height - height) / 2 + (index % 2 ? 1 : -1) * (p - 0.5) * 34
          }
        }
      }
    }

    Column {
      anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: card.tileH / 2 + Math.abs(card.dy) / 2 + 80 * card.unit }
      spacing: 8 * card.unit

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Pantallas enlazadas"
        color: Color.foreground
        font.family: Style.fontFamily
        font.pixelSize: Math.round(28 * card.unit)
        font.weight: Font.Light
        font.letterSpacing: 2
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "lan-mouse  ·  el puntero cruza por el borde " + root.positionText
        color: Color.accent
        font.family: Style.fontFamily
        font.pixelSize: Math.round(14 * card.unit)
        font.letterSpacing: 1
        opacity: root.linkEdge
      }
    }
  }

  // Brillo sobre el borde real de la pantalla.
  component EdgeGlow: Item {
    id: edge
    property var screenRef: null
    readonly property string pos: root.peerPosition
    readonly property bool vertical: pos === "left" || pos === "right"
    readonly property real depth: 130

    // Franja completa (al enlazar / desconectar).
    Item {
      width: edge.vertical ? edge.depth : edge.width
      height: edge.vertical ? edge.height : edge.depth
      x: edge.pos === "right" ? edge.width - width : 0
      y: edge.pos === "bottom" ? edge.height - height : 0
      opacity: root.edgeGlow

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: edge.vertical ? Gradient.Horizontal : Gradient.Vertical
          GradientStop {
            position: 0
            color: (edge.pos === "right" || edge.pos === "bottom") ? "transparent"
              : Qt.rgba(root.edgeColor.r, root.edgeColor.g, root.edgeColor.b, 0.6)
          }
          GradientStop {
            position: 1
            color: (edge.pos === "right" || edge.pos === "bottom")
              ? Qt.rgba(root.edgeColor.r, root.edgeColor.g, root.edgeColor.b, 0.6) : "transparent"
          }
        }
      }
      Rectangle {
        width: edge.vertical ? 4 : parent.width
        height: edge.vertical ? parent.height : 4
        x: edge.pos === "right" ? parent.width - width : 0
        y: edge.pos === "bottom" ? parent.height - height : 0
        color: root.edgeColor
      }
    }

    Text {
      visible: root.edgeLabel !== ""
      opacity: root.edgeGlow
      text: root.edgeLabel
      color: Color.foreground
      font.family: Style.fontFamily
      font.pixelSize: 14
      font.letterSpacing: 1
      x: edge.pos === "right" ? edge.width - width - edge.depth - 10
        : edge.pos === "left" ? edge.depth + 10 : (edge.width - width) / 2
      y: edge.pos === "bottom" ? edge.height - height - edge.depth - 10
        : edge.pos === "top" ? edge.depth + 10 : (edge.height - height) / 2
    }

    // Punto de cruce: un segmento corto centrado donde pasó el puntero.
    Item {
      id: spot
      readonly property real len: 260
      readonly property real along: {
        if (!edge.screenRef) return (edge.vertical ? edge.height : edge.width) / 2
        var c = edge.vertical ? root.crossY - edge.screenRef.y : root.crossX - edge.screenRef.x
        var full = edge.vertical ? edge.height : edge.width
        return (root.crossX < 0 || c < 0 || c > full) ? full / 2 : c
      }
      width: edge.vertical ? 40 : len
      height: edge.vertical ? len : 40
      x: edge.vertical ? (edge.pos === "right" ? edge.width - width : 0) : along - len / 2
      y: edge.vertical ? along - len / 2 : (edge.pos === "bottom" ? edge.height - height : 0)
      opacity: root.crossGlow

      Rectangle {
        anchors.centerIn: parent
        width: edge.vertical ? 34 : parent.width
        height: edge.vertical ? parent.height : 34
        anchors.horizontalCenterOffset: edge.vertical ? (edge.pos === "right" ? 17 : -17) : 0
        anchors.verticalCenterOffset: edge.vertical ? 0 : (edge.pos === "bottom" ? 17 : -17)
        radius: 17
        color: Qt.rgba(root.edgeColor.r, root.edgeColor.g, root.edgeColor.b, 0.35)
      }
      Rectangle {
        width: edge.vertical ? 4 : parent.width * 0.7
        height: edge.vertical ? parent.height * 0.7 : 4
        radius: 2
        x: edge.vertical ? (edge.pos === "right" ? parent.width - width : 0) : (parent.width - width) / 2
        y: edge.vertical ? (parent.height - height) / 2 : (edge.pos === "bottom" ? parent.height - height : 0)
        color: root.edgeColor
      }
    }
  }

  // ------------------------------------------------------------------ ventanas
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      readonly property bool isEdge: String(modelData.name) === root.edgeScreen

      screen: modelData
      // Solo mapeada mientras hay algo que mostrar: en reposo no hay superficie.
      // Una pantalla que aparece con la escena puesta (SUNSHINE-VD, o el panel
      // que vuelve al desconectar) nace ya tapada, sin destello.
      visible: root.streamActive || (root.linkActive && isEdge)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "eztvn-enlace"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        color: Color.background
        opacity: 0.86 * root.linkScrim
        visible: win.isEdge && root.linkScrim > 0.001
      }

      LinkCard {
        anchors.fill: parent
        visible: win.isEdge && root.linkCard > 0.001
      }

      EdgeGlow {
        anchors.fill: parent
        screenRef: win.modelData
        visible: win.isEdge && (root.edgeGlow > 0.001 || root.crossGlow > 0.001)
      }

      StreamScene {
        anchors.fill: parent
        screenRef: win.modelData
        visible: root.veil > 0.001
      }
    }
  }
}
