import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Temporizador compartido + recordatorio de descanso visual.
//
// La barra se instancia una vez por monitor, así que el estado (dos epoch en
// milisegundos) vive en archivos bajo ~/.local/state/eztvn.timer y cada
// instancia los observa con FileView. Eso mantiene la cuenta y el overlay
// sincronizados entre pantallas y sobrevive a una recarga del shell.
//
// El descanso es periódico: con el modo encendido, cada `eyeIntervalMinutes`
// aparece un overlay de `eyeDurationSeconds`; los dos tiempos se configuran
// en shell.json. El estado guarda solo el instante del próximo descanso, así
// que el modo sobrevive reinicios y saltarse un descanso no lo apaga.
//
// El aviso de fin del temporizador lo programa systemd-run (unidad
// transitoria), no QML: si el shell se reinicia a mitad de la cuenta, el
// aviso sigue llegando.
BarWidget {
  id: root
  moduleName: "eztvn.timer"

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/eztvn.timer"
  readonly property string timerPath: root.stateDir + "/timer-end"
  readonly property string eyePath: root.stateDir + "/eye-next"
  readonly property string notifyScript: Qt.resolvedUrl("notify.sh").toString().replace("file://", "")

  function clampInt(value, min, max, fallback) {
    var number = Math.round(Number(value))
    if (!isFinite(number)) number = fallback
    return Math.max(min, Math.min(max, number))
  }

  readonly property int eyeIntervalMinutes: clampInt(setting("eyeIntervalMinutes", 20), 1, 240, 20)
  readonly property int eyeDurationSeconds: clampInt(setting("eyeDurationSeconds", 30), 5, 300, 30)
  readonly property double eyeIntervalMs: eyeIntervalMinutes * 60000
  readonly property double eyeDurationMs: eyeDurationSeconds * 1000

  property int timerMinutes: clampInt(setting("timerMinutes", 25), 1, 240, 25)

  readonly property var ownScreen: root.QsWindow.window ? root.QsWindow.window.screen : null
  // Un solo dueño del target IPC; el resto de instancias reciben los cambios
  // por el archivo de estado, así que no necesitan handler propio.
  readonly property bool ipcOwner: {
    var screens = Quickshell.screens
    return screens.length > 0 && root.ownScreen && root.ownScreen.name === screens[0].name
  }

  property double now: Date.now()
  property double timerEnd: 0
  property double eyeNext: 0

  readonly property bool timerActive: root.timerEnd > root.now
  readonly property double timerRemainingMs: Math.max(0, root.timerEnd - root.now)

  readonly property bool eyeArmed: root.eyeNext > 0
  readonly property bool eyeBreakActive: root.eyeArmed
    && root.now >= root.eyeNext
    && root.now < root.eyeNext + root.eyeDurationMs
  readonly property double eyeBreakRemainingMs: root.eyeBreakActive
    ? Math.max(0, root.eyeNext + root.eyeDurationMs - root.now) : 0
  readonly property double eyeNextInMs: root.eyeArmed && !root.eyeBreakActive
    ? Math.max(0, root.eyeNext - root.now) : 0

  readonly property string barLabel: root.timerActive
    ? "󰔛 " + Format.clock(root.timerRemainingMs)
    : (root.eyeArmed
      ? (root.eyeBreakActive ? "󰈈 " + Format.clock(root.eyeBreakRemainingMs) : "󰈈")
      : "󰔛")

  readonly property string tooltipText: root.eyeBreakActive
    ? "Descanso visual · quedan " + Format.clock(root.eyeBreakRemainingMs)
    : (root.eyeArmed
      ? "Protección visual activa\nCada " + root.eyeIntervalMinutes + " min · "
        + root.eyeDurationSeconds + " s · próximo en " + Format.clock(root.eyeNextInMs)
        + "\nClic para gestionar"
      : (root.timerActive
        ? "Temporizador: quedan " + Format.clock(root.timerRemainingMs) + "\nClic para gestionar"
        : "Temporizador y descanso visual\nClic para abrir"))

  // ---------------------------------------------------------------- estado

  function parseEnd(raw) {
    var value = Number(String(raw || "").trim())
    return isFinite(value) && value > 0 ? value : 0
  }

  function applyTimer(raw) { root.timerEnd = parseEnd(raw) }
  function applyEyeNext(raw) { root.eyeNext = parseEnd(raw) }

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
    stateWriter.command = ["bash", "-c", "printf '%s' \"$2\" > \"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"", "--", item.path, item.value]
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

  function writeEyeNext(ms) {
    root.eyeNext = Math.max(0, ms)
    root.now = Date.now()
    root.writeStateFile(root.eyePath, root.eyeNext)
  }

  function startTimer(minutes) {
    var mins = clampInt(minutes, 1, 240, root.timerMinutes)
    root.timerMinutes = mins
    root.writeTimerEnd(Date.now() + mins * 60000)
    root.scheduleAlert(mins)
  }

  function stopTimer() {
    root.writeTimerEnd(0)
    root.cancelAlert()
  }

  // ------------------------------------------------------------- descanso

  function enableEye() {
    if (root.eyeArmed) return
    root.writeEyeNext(Date.now() + root.eyeIntervalMs)
  }

  function disableEye() {
    root.writeEyeNext(0)
  }

  function toggleEye() {
    if (root.eyeArmed) root.disableEye()
    else root.enableEye()
  }

  // Esc durante el descanso salta solo ese descanso; el modo sigue armado.
  function skipEyeBreak() {
    if (!root.eyeArmed) return
    var next = root.eyeNext
    if (root.now < next + root.eyeDurationMs) next += root.eyeIntervalMs
    root.writeEyeNext(next)
  }

  // Solo una instancia avanza el calendario cuando el descanso ya terminó.
  function advanceEyeSchedule() {
    if (!root.eyeArmed || !root.ipcOwner) return
    if (root.now < root.eyeNext + root.eyeDurationMs) return
    var overdue = root.now - (root.eyeNext + root.eyeDurationMs)
    var steps = Math.max(1, Math.ceil(overdue / root.eyeIntervalMs))
    root.writeEyeNext(root.eyeNext + steps * root.eyeIntervalMs)
  }

  // ---------------------------------------------------------------- avisos

  function stopUnitsCommand() {
    return "systemctl --user list-units --all --plain --no-legend "
      + Util.shellQuote("eztvn-timer-timer-*")
      + " | awk '{print $1}' | xargs -r systemctl --user stop >/dev/null 2>&1 || true"
  }

  function scheduleAlert(minutes) {
    var unit = "eztvn-timer-timer-" + Date.now()
    var seconds = Math.max(1, Math.round(minutes * 60))
    alertProc.command = ["bash", "-c",
      stopUnitsCommand() + "; "
      + "exec systemd-run --user --collect --unit=" + Util.shellQuote(unit)
      + " --on-active=" + seconds + " "
      + Util.shellQuote(root.notifyScript) + " " + minutes]
    if (!alertProc.running) alertProc.running = true
  }

  function cancelAlert() {
    if (alertProc.running) return
    cancelProc.command = ["bash", "-c", stopUnitsCommand()]
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
    active: root.timerActive || root.eyeArmed
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
    function stop(): void { root.stopTimer() }
    function eye(): void { root.toggleEye() }
    function eyeOn(): void { root.enableEye() }
    function eyeOff(): void { root.disableEye() }
    function eyeSkip(): void { root.skipEyeBreak() }
    function status(): string {
      return JSON.stringify({
        timerActive: root.timerActive,
        timerRemainingMs: Math.round(root.timerRemainingMs),
        eyeArmed: root.eyeArmed,
        eyeBreakActive: root.eyeBreakActive,
        eyeBreakRemainingMs: Math.round(root.eyeBreakRemainingMs),
        eyeNextInMs: Math.round(root.eyeNextInMs)
      })
    }
  }

  // -------------------------------------------------------------- descanso
  //
  // Una ventana por instancia (una barra por monitor): entre todas cubren
  // todas las pantallas. La opacidad es total: la idea es no mirar la pantalla.

  PanelWindow {
    id: eyeOverlay
    visible: root.eyeBreakActive && root.ownScreen !== null
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
      onCloseRequested: root.skipEyeBreak()

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
          text: Format.clock(root.eyeBreakRemainingMs)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.displayLarge * 2.4)
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.eyeDurationSeconds + " s · se cierra solo · Esc para saltarlo"
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
    onFileChanged: reload()
    onLoadFailed: root.applyTimer("0")
  }

  FileView {
    id: eyeFile
    path: root.eyePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyEyeNext(text())
    onFileChanged: reload()
    onLoadFailed: root.applyEyeNext("0")
  }

  Process {
    id: ensureState
    command: ["bash", "-c",
      "mkdir -p \"$1\"; rm -f \"$1/eye-end\"; for f in timer-end eye-next; do [[ -e \"$1/$f\" ]] || printf 0 > \"$1/$f\"; done",
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
    interval: 1000
    repeat: true
    running: root.timerActive || root.eyeArmed
    onTriggered: {
      root.now = Date.now()
      root.advanceEyeSchedule()
    }
  }

  Component.onCompleted: {
    root.now = Date.now()
    ensureState.running = true
  }
}
