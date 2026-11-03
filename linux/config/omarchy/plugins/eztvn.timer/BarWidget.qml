import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Temporizador compartido + descanso visual.
//
// La barra se instancia una vez por monitor, así que el estado (dos epoch en
// milisegundos) vive en archivos bajo ~/.local/state/eztvn.timer y cada
// instancia los observa con FileView. Eso mantiene la cuenta y el overlay
// sincronizados entre pantallas y sobrevive a una recarga del shell.
//
// El aviso de fin lo programa systemd-run (unidad transitoria), no QML: si el
// shell se reinicia a mitad de la cuenta, el aviso sigue llegando.
BarWidget {
  id: root
  moduleName: "eztvn.timer"

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/eztvn.timer"
  readonly property string timerPath: root.stateDir + "/timer-end"
  readonly property string eyePath: root.stateDir + "/eye-end"
  readonly property string notifyScript: Qt.resolvedUrl("notify.sh").toString().replace("file://", "")

  readonly property int eyeMinutes: Math.max(1, Math.min(180, Math.round(Number(setting("eyeMinutes", 20)) || 20)))
  property int timerMinutes: Math.max(1, Math.min(240, Math.round(Number(setting("timerMinutes", 25)) || 25)))

  readonly property var ownScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
  // Un solo dueño del target IPC; el resto de instancias reciben los cambios
  // por el archivo de estado, así que no necesitan handler propio.
  readonly property bool ipcOwner: {
    var screens = Quickshell.screens
    return screens.length > 0 && root.ownScreen && root.ownScreen.name === screens[0].name
  }

  property double now: Date.now()
  property double timerEnd: 0
  property double eyeEnd: 0

  readonly property bool timerActive: root.timerEnd > root.now
  readonly property bool eyeActive: root.eyeEnd > root.now
  readonly property double timerRemainingMs: Math.max(0, root.timerEnd - root.now)
  readonly property double eyeRemainingMs: Math.max(0, root.eyeEnd - root.now)

  readonly property string barLabel: root.eyeActive
    ? "󰈈 " + Format.clock(root.eyeRemainingMs)
    : (root.timerActive ? "󰔛 " + Format.clock(root.timerRemainingMs) : "󰔛")

  readonly property string tooltipText: root.eyeActive
    ? "Descanso visual: quedan " + Format.clock(root.eyeRemainingMs) + "\nClic para gestionar"
    : (root.timerActive
      ? "Temporizador: quedan " + Format.clock(root.timerRemainingMs) + "\nClic para gestionar"
      : "Temporizador y descanso visual\nClic para abrir")

  // ---------------------------------------------------------------- estado

  function parseEnd(raw) {
    var value = Number(String(raw || "").trim())
    return isFinite(value) && value > 0 ? value : 0
  }

  function applyTimer(raw) { root.timerEnd = parseEnd(raw) }
  function applyEye(raw) { root.eyeEnd = parseEnd(raw) }

  function clampMinutes(value, max) {
    var minutes = Math.round(Number(value))
    if (!isFinite(minutes)) minutes = 1
    return Math.max(1, Math.min(max, minutes))
  }

  // Escritura fuera de FileView: setText dispara el watcher antes de que el
  // contenido nuevo sea visible, y la lectura vieja (0) borraba el estado
  // recién puesto. Un proceso escribe el archivo y deja que el watcher lea
  // contenido ya asentado.
  property var pendingWrite: null

  function writeStateFile(path, value) {
    var item = { path: path, value: String(Math.max(0, Math.round(value))) }
    if (stateWriter.running) {
      root.pendingWrite = item
      return
    }
    root.pendingWrite = null
    stateWriter.command = ["bash", "-c", "printf '%s' \"$2\" > \"$1\"", "--", item.path, item.value]
    stateWriter.running = true
  }

  function flushPendingWrite() {
    var next = root.pendingWrite
    if (!next) return
    root.pendingWrite = null
    root.writeStateFile(next.path, Number(next.value))
  }

  function writeTimerEnd(ms) {
    root.timerEnd = Math.max(0, ms)
    root.now = Date.now()
    root.writeStateFile(root.timerPath, root.timerEnd)
  }

  function writeEyeEnd(ms) {
    root.eyeEnd = Math.max(0, ms)
    root.now = Date.now()
    root.writeStateFile(root.eyePath, root.eyeEnd)
  }

  function startTimer(minutes) {
    var mins = clampMinutes(minutes, 240)
    root.timerMinutes = mins
    writeTimerEnd(Date.now() + mins * 60000)
    scheduleAlert("timer", mins)
  }

  function stopTimer() {
    writeTimerEnd(0)
    cancelAlert("timer")
  }

  function startEye() {
    writeEyeEnd(Date.now() + root.eyeMinutes * 60000)
    scheduleAlert("eye", root.eyeMinutes)
  }

  function stopEye() {
    writeEyeEnd(0)
    cancelAlert("eye")
  }

  function toggleEye() {
    if (root.eyeActive) root.stopEye()
    else root.startEye()
  }

  // ---------------------------------------------------------------- avisos

  function unitPattern(kind) {
    return "eztvn-timer-" + kind + "-*"
  }

  function stopUnitsCommand(kind) {
    return "systemctl --user list-units --all --plain --no-legend "
      + Util.shellQuote(unitPattern(kind))
      + " | awk '{print $1}' | xargs -r systemctl --user stop >/dev/null 2>&1 || true"
  }

  function scheduleAlert(kind, minutes) {
    var unit = "eztvn-timer-" + kind + "-" + Date.now()
    var seconds = Math.max(1, Math.round(minutes * 60))
    alertProc.command = ["bash", "-c",
      stopUnitsCommand(kind) + "; "
      + "exec systemd-run --user --collect --unit=" + Util.shellQuote(unit)
      + " --on-active=" + seconds + " "
      + Util.shellQuote(root.notifyScript) + " " + Util.shellQuote(kind) + " " + minutes]
    if (!alertProc.running) alertProc.running = true
  }

  function cancelAlert(kind) {
    if (alertProc.running) return
    cancelProc.command = ["bash", "-c", stopUnitsCommand(kind)]
    if (!cancelProc.running) cancelProc.running = true
  }

  // ---------------------------------------------------------------- barra

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    tooltipText: root.tooltipText
    active: root.timerActive || root.eyeActive
    activeColor: Color.accent
    horizontalMargin: 8.5
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    enabled: root.ipcOwner
    target: "eztvn.timer"

    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
    function show(): void { root.broadcast("open") }
    function hide(): void { root.broadcast("close") }
    function toggle(): void { root.broadcast("togglePanel") }
    function countdown(minutes: string): void { root.startTimer(Number(minutes)) }
    function echo(text: string): string { return text }
    function stop(): void { root.stopTimer() }
    function eye(): void { root.toggleEye() }
    function startEye(): void { root.startEye() }
    function stopEye(): void { root.stopEye() }
    function status(): string {
      return JSON.stringify({
        timerActive: root.timerActive,
        timerRemainingMs: Math.round(root.timerRemainingMs),
        eyeActive: root.eyeActive,
        eyeRemainingMs: Math.round(root.eyeRemainingMs)
      })
    }
  }

  // -------------------------------------------------------------- descanso
  //
  // Una ventana por instancia (una barra por monitor): entre todas cubren
  // todas las pantallas. La opacidad es total: la idea es no mirar la pantalla.

  PanelWindow {
    id: eyeOverlay
    visible: root.eyeActive && root.ownScreen !== null
    screen: root.ownScreen
    color: Color.background
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    WlrLayershell.namespace: "eztvn-eye-break"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { eyeKeys.forceActiveFocus() })
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      onWheel: function(wheel) { wheel.accepted = true }
    }

    PanelKeyCatcher {
      id: eyeKeys
      anchors.fill: parent
      onCloseRequested: root.stopEye()

      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(80), Style.space(720))
        spacing: Style.space(18)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "󰈈"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.displayLarge * 3)
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Descansa la vista"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Mira algo lejos, al fondo de la habitación."
          color: Qt.darker(Color.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: Format.clock(root.eyeRemainingMs)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.displayLarge * 2.4)
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Vuelve a la pantalla cuando llegue a cero · Esc para terminar antes"
          color: Qt.darker(Color.foreground, 1.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ------------------------------------------------------------- ficheros

  FileView {
    id: timerFile
    path: root.timerPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyTimer(text())
    onFileChanged: root.applyTimer(text())
    onLoadFailed: root.applyTimer("0")
  }

  FileView {
    id: eyeFile
    path: root.eyePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyEye(text())
    onFileChanged: root.applyEye(text())
    onLoadFailed: root.applyEye("0")
  }

  Process {
    id: ensureState
    command: ["bash", "-c",
      "mkdir -p \"$1\"; for f in timer-end eye-end; do [[ -e \"$1/$f\" ]] || printf 0 > \"$1/$f\"; done",
      "--", root.stateDir]
    onExited: {
      timerFile.reload()
      eyeFile.reload()
    }
  }

  Process { id: alertProc }
  Process { id: cancelProc }

  Process {
    id: stateWriter
    onExited: root.flushPendingWrite()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.timerActive || root.eyeActive
    onTriggered: root.now = Date.now()
  }

  Component.onCompleted: {
    root.now = Date.now()
    ensureState.running = true
  }
}
