import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool releasePending: false
  // Quickshell aísla el scope de la superficie del lock: Service.qml no puede
  // tocar el LockView por id (ReferenceError: lockView is not defined). Estos
  // dos estados los consume el LockView para animarse.
  property bool lockSecure: false
  property bool lockReleasing: false
  // "" esperando · "ok" huella correcta · "denied" el dedo no coincide.
  property string fingerprintResult: ""
  // El lock apaga el panel por DPMS a los 5s de bloquear. Mientras la pantalla
  // está apagada no tiene sentido mantener el lector escaneando: el firmware
  // ELAN se deshabilita solo por temperatura si escanea de corrido, y así queda
  // muerto justo cuando volvés. Se escanea sólo con la imagen encendida.
  property bool displayOn: true
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  // Espera entre intentos de huella. Sin esto el reintento era fijo de 250 ms y,
  // cuando el lector contesta al instante con error, se convertía en un bucle de
  // 3-4 intentos por segundo que termina trabando el sensor ELAN.
  property int fingerprintBackoff: 1000
  property double fingerprintAttemptStartedAt: 0
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true

    // Con las pantallas ya presentes (el caso normal: SUPER+L en una sesión
    // viva) no hay nada que estabilizar: esperar los 500ms del timer era la
    // razón por la que la animación de entrada arrancaba tarde. El margen queda
    // sólo para cuando todavía no hay salida real.
    if (hasRealScreen()) {
      requestSessionLock()
      // Si el compositor no tomó el lock al toque, el polling de siempre sigue
      // insistiendo (se detiene solo cuando la superficie queda arriba).
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintBackoff = 1000
    fingerprintAttemptStartedAt = 0
    fingerprintResult = ""
    fingerprintRetryTimer.stop()
    fingerprintSuccessTimer.stop()
    fingerprintFeedbackTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    // Si venía una salida animada, se cancela: este bloqueo es nuevo y no debe
    // soltarse cuando termine el timer de la salida anterior.
    releaseTimer.stop()
    releasePending = false
    lockReleasing = false
    displayOn = true
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  // Cerrar el lock no es instantáneo: primero se disuelve en pantalla y recién
  // después se suelta la sesión. Mientras dura, la sesión sigue bloqueada y
  // `secure`, así que no hay ningún instante expuesto de más.
  function finishUnlock() {
    if (!root.locked && !lockRequested) return
    if (releasePending) return

    releasePending = true
    idleBlankTimer.stop()
    // El timer se arma ANTES de la animación: si la animación fallara, la sesión
    // igual se suelta (nunca quedarse colgado en un lock que ya se autenticó).
    releaseTimer.restart()
    lockReleasing = true
  }

  function releaseLock() {
    releaseTimer.stop()
    releasePending = false

    lockRequested = false
    lockReleasing = false
    lockSecure = false
    sessionLock.locked = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()

    if (!displayOn) {
      displayOn = true
      // Re-armar enseguida: al volver la imagen el dedo tiene que estar a un
      // toque de distancia.
      startFingerprint()
    }
  }

  function runBlank() {
    if (!blankProcess.running) blankProcess.running = true

    // Se corta el reintento (así el lector enfría con la pantalla apagada) pero
    // NO se aborta el intento en curso: abortarlo dejaba el contexto colgado y
    // después no se podía re-armar (el dedo no hacía nada al volver). Si el dedo
    // llega igual, entra: el intento sigue escuchando hasta su timeout.
    displayOn = false
    fingerprintRetryTimer.stop()
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured || !displayOn) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    fingerprintAttemptStartedAt = Date.now()
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
      scheduleFingerprintRetry()
    }
  }

  // pam_fprintd contesta al instante cuando el sensor está trabado ("device busy",
  // "disabled to prevent overheating", PAM code 9). Reintentar cada 250 ms en ese
  // estado es lo que lo deja trabado hasta que fprintd se reinicia —y encima
  // libfprint lo apaga por temperatura—. Si el intento volvió demasiado rápido se
  // espera cada vez más (1s → 8s); si duró lo normal (huella que no coincidió o el
  // timeout de 30s del lector) con 1s alcanza para que quede listo otra vez.
  function scheduleFingerprintRetry() {
    if (!lockRequested || !fingerprintConfigured || !displayOn) return

    var elapsed = fingerprintAttemptStartedAt > 0 ? Date.now() - fingerprintAttemptStartedAt : 0
    fingerprintBackoff = elapsed < 1500 ? Math.min(fingerprintBackoff * 2, 8000) : 1000

    fingerprintRetryTimer.interval = fingerprintBackoff
    fingerprintRetryTimer.restart()
  }

  // pam_fprintd manda "Failed to match fingerprint" cuando hay un dedo puesto
  // que no coincide (y sigue escuchando). Eso se anima al toque; el timeout de
  // 30s sin dedo no, para no sacudir la caja porque sí.
  function handleFingerprintMessage(message) {
    if (!lockRequested) return

    var text = String(message || "").toLowerCase()
    if (text.indexOf("match fingerprint") >= 0) {
      fingerprintResult = "denied"
      fingerprintFeedbackTimer.restart()
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      // El "✓" se ve antes de soltar: un toque de confirmación y recién ahí
      // arranca la salida animada.
      fingerprintResult = "ok"
      fingerprintSuccessTimer.restart()
      return
    }

    scheduleFingerprintRetry()
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
        // Acá la superficie ya está arriba: el LockView reacciona a esto
        // pidiendo foco y arrancando la animación de entrada. (Antes el campo
        // pedía foco ~500ms antes de que existiera la superficie, el pedido se
        // perdía y el click era el único camino para poder escribir.)
        root.lockSecure = true
      } else {
        // Higiene: si la superficie deja de estar segura por cualquier camino,
        // el próximo bloqueo tiene que volver a disparar la animación y el foco.
        root.lockSecure = false
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        root.releasePending = false
        releaseTimer.stop()
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        // El reveal se dispara desde acá, cuando la superficie ya está arriba
        // (`secure`) y por lo tanto se ve; si se disparara al bloquear, la
        // animación terminaría antes de que el lock apareciera en pantalla.
        revealOnLoad: false
        lockSecure: root.lockSecure
        lockReleasing: root.lockReleasing
        fingerprintResult: root.fingerprintResult
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested && !root.releasePending
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onPamMessage: function(message, type) {
      root.handleFingerprintMessage(message)
    }

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      root.scheduleFingerprintRetry()
    }
  }

  // Confirmación de huella: se ve el ✓ y después se suelta la sesión.
  Timer {
    id: fingerprintSuccessTimer
    interval: 320
    repeat: false
    onTriggered: root.finishUnlock()
  }

  // El feedback de "no coincide" se limpia solo para volver al icono normal.
  Timer {
    id: fingerprintFeedbackTimer
    interval: 900
    repeat: false
    onTriggered: root.fingerprintResult = ""
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 1000
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  // La salida animada tarda lo que dice LockView.exitDuration (mantenerlos
  // iguales): recién al terminar se suelta la sesión.
  Timer {
    id: releaseTimer
    interval: 320
    repeat: false
    onTriggered: root.releaseLock()
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
