import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.Commons
import qs.Ui

Item {
  id: root

  // Red de seguridad: si nadie tiene el foco (por ejemplo al volver de DPMS o de
  // una suspensión) la primera tecla recupera el campo en vez de perderse.
  focus: true
  Keys.onPressed: function(event) {
    if (!passwordInput.activeFocus) forcePasswordFocus()
  }

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  // 0 = nada visible, 1 = lock asentado. La entrada lo lleva de 0 a 1.
  property real reveal: 0
  // Segunda fase de la entrada: la sombra del campo florece y después se asienta.
  property real haloSettle: 0
  // La salida es la inversa de `reveal` (vuelve a 0). Mientras dura, `exiting`
  // apaga el velo y abre el blur, así el corte al escritorio se siente como un
  // enfocar en vez de un salto. El servicio suelta la sesión al terminar.
  property bool exiting: false
  readonly property int exitDuration: 280
  // El lock real dispara la entrada recién cuando la superficie ya está arriba
  // (secure), porque en ese momento es cuando se ve; el preview la dispara al
  // mostrarse, para poder verla sin bloquear la sesión.
  property bool revealOnLoad: true
  // Estado que publica el servicio. Quickshell aísla el scope de la superficie,
  // así que Service.qml NO puede tocar este item por id: se comunican por acá.
  property bool lockSecure: false
  property bool lockReleasing: false
  // Resultado de la huella: "" (esperando), "ok" o "denied" (el dedo está
  // puesto pero no coincide). Lo publica el servicio desde pam_fprintd.
  property string fingerprintResult: ""

  readonly property bool fpOk: fingerprintResult === "ok"
  readonly property bool fpDenied: fingerprintResult === "denied"
  // Verde para confirmar, rojo para rechazar: los únicos dos colores que se
  // salen de la paleta, sólo en el icono y el borde del campo.
  readonly property color fpColor: fpDenied ? "#ff7b72" : "#7ee787"

  // Valores animados del feedback (los visuals sólo leen de acá).
  property real fpRingScale: 1
  property real fpRingOpacity: 0
  property real fpGlyphScale: 1
  property real fpFlash: 0
  property real shakeX: 0

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 381
  readonly property int fieldHeight: 67
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  // Al volver de DPMS/suspensión la ventana se reactiva y el foco activo no
  // siempre se restaura solo: sin esto había que clickear el campo.
  Window.onActiveChanged: {
    if (Window.active) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    // El preview crea el LockView ya visible (loadBackground nace en true), así
    // que el cambio de propiedad no dispara la entrada: se dispara acá.
    if (root.revealOnLoad && loadBackground) playReveal()
    // Si la superficie se crea con la sesión ya segura, el cambio de propiedad
    // no llega: la entrada y el foco se piden también al nacer.
    if (root.lockSecure) {
      playReveal()
      Qt.callLater(forcePasswordFocus)
    }
  }

  onLockSecureChanged: {
    if (root.lockSecure) {
      playReveal()
      Qt.callLater(forcePasswordFocus)
    }
  }

  onLockReleasingChanged: {
    if (root.lockReleasing) playExit()
  }

  // Entrada del lock. El contenido entra en 620 ms (outCubic: rápido al
  // principio, se posa suave), el fondo hace un "focus pull" y después la
  // sombra del campo termina de asentarse en 1.4 s. Una sola pasada: nada late
  // para siempre, así la pantalla quieta no gasta GPU.
  function playReveal() {
    root.exiting = false
    root.reveal = 0
    root.haloSettle = 0
    revealSeq.restart()
  }

  // Salida: el lock se disuelve (el servicio espera exitDuration antes de
  // soltar la sesión, así que la pantalla nunca queda expuesta antes de tiempo).
  function playExit() {
    root.exiting = true
    exitAnim.restart()
  }

  onLoadBackgroundChanged: {
    if (root.revealOnLoad && loadBackground) playReveal()
  }

  SequentialAnimation {
    id: revealSeq
    NumberAnimation {
      target: root
      property: "reveal"
      from: 0
      to: 1
      duration: 620
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "haloSettle"
      from: 0
      to: 1
      duration: 1400
      easing.type: Easing.InOutQuad
    }
  }

  // Huella correcta: el glifo entra con un pop, el anillo se expande y el borde
  // del campo da un destello verde. Se ve antes de que arranque la salida.
  ParallelAnimation {
    id: fpOkAnim
    NumberAnimation { target: root; property: "fpRingOpacity"; from: 0.85; to: 0; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fpRingScale"; from: 1.0; to: 2.0; duration: 520; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fpFlash"; from: 0.95; to: 0; duration: 620; easing.type: Easing.OutCubic }
    SequentialAnimation {
      NumberAnimation { target: root; property: "fpGlyphScale"; from: 0.55; to: 1.3; duration: 150; easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "fpGlyphScale"; to: 1.0; duration: 220; easing.type: Easing.InOutQuad }
    }
  }

  // Huella que no coincide: la caja se sacude, el anillo se cierra y el borde
  // destella rojo. No bloquea nada: el lector sigue escuchando.
  ParallelAnimation {
    id: fpDeniedAnim
    NumberAnimation { target: root; property: "fpFlash"; from: 0.9; to: 0; duration: 460; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fpRingOpacity"; from: 0.7; to: 0; duration: 280 }
    NumberAnimation { target: root; property: "fpRingScale"; from: 1.35; to: 0.85; duration: 280 }
    SequentialAnimation {
      NumberAnimation { target: root; property: "shakeX"; from: 0; to: -8; duration: 50; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "shakeX"; to: 7; duration: 60 }
      NumberAnimation { target: root; property: "shakeX"; to: -4; duration: 60 }
      NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 70 }
    }
  }

  onFingerprintResultChanged: {
    if (root.fpOk) fpOkAnim.restart()
    else if (root.fpDenied) fpDeniedAnim.restart()
  }

  NumberAnimation {
    id: exitAnim
    target: root
    property: "reveal"
    to: 0
    duration: root.exitDuration
    easing.type: Easing.InCubic
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    id: backdrop
    anchors.fill: parent
    color: Color.background

    // Fondo: el wallpaper de siempre, blur incluido. La entrada hace un "focus
    // pull" (el blur se cierra y la imagen se asienta) y la salida lo abre del
    // todo, así el corte al escritorio se siente como un enfocar, no un salto.
    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
      scale: (1.045 - 0.045 * root.reveal) + (root.exiting ? 0.05 * (1.0 - root.reveal) : 0)
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: root.exiting ? 1.25 * root.reveal : (1.6 - 0.35 * root.reveal)
      contrast: root.exiting ? -0.08 * root.reveal : (-0.08 - 0.05 * (1.0 - root.reveal))
    }

    // Velo: al entrar, el lock aparece saliendo de un oscurecido (cine). Al
    // salir no participa: ahí se disuelve el contenido y el fondo se aclara.
    Rectangle {
      anchors.fill: parent
      color: "#000000"
      opacity: root.exiting ? 0 : 0.85 * Math.pow(1.0 - root.reveal, 2)
    }

    // Sombra suave detrás del campo: le da volumen sobre cualquier wallpaper y
    // es lo que "florece" durante la entrada.
    Rectangle {
      id: fieldShadowShape
      anchors.centerIn: inputField
      width: inputField.width + 260
      height: inputField.height + 160
      radius: height / 2
      color: "#000000"
      visible: false
    }

    MultiEffect {
      anchors.fill: fieldShadowShape
      source: fieldShadowShape
      blurEnabled: true
      blur: 1.0
      blurMax: 96
      opacity: 0.45 * root.reveal * (1.0 - 0.5 * root.haloSettle)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      color: Color.lock.background
      borderSpec: root.inputBorderSpec
      radius: Style.cornerRadius
      clip: true
      // Entrada: micro-zoom (0.97 → 1) y sube 16 px. La salida es la misma
      // curva al revés: el campo se posa y se disuelve.
      scale: 0.97 + 0.03 * root.reveal
      opacity: Math.min(1, root.reveal * 1.25)
      transform: Translate { x: root.shakeX; y: (1 - root.reveal) * 16 }

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        // El texto entra último: primero se ve el campo, después el "Enter
        // Password". Le da secuencia a la entrada.
        opacity: Math.max(0, (root.reveal - 0.35) / 0.65)
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Huella + feedback, dentro del campo sobre el borde derecho. El badge
      // mantiene el layout quieto mientras el glifo cambia (huella → ✓ / ✕).
      Item {
        id: fingerprintBadge
        objectName: "fingerprintIndicator"
        visible: root.fingerprintConfigured
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(fingerprintIcon.implicitWidth, fingerprintGlyph.implicitWidth)
        height: Math.max(fingerprintIcon.implicitHeight, fingerprintGlyph.implicitHeight)

        // Anillo: se abre al confirmar, se cierra al rechazar.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 12
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1.5
          border.color: root.fpColor
          opacity: root.fpRingOpacity
          scale: root.fpRingScale
        }

        Text {
          id: fingerprintIcon
          anchors.centerIn: parent
          text: "󰈷"
          color: Color.lock.placeholder
          font.family: Style.font.family
          font.pixelSize: Math.round(root.fieldFontSize * 1.1)
          opacity: root.fingerprintResult === "" ? 1 : 0
        }

        Text {
          id: fingerprintGlyph
          anchors.centerIn: parent
          text: root.fpDenied ? "✕" : "✓"
          color: root.fpColor
          font.family: Style.font.family
          font.pixelSize: Math.round(root.fieldFontSize * 1.15)
          opacity: root.fingerprintResult === "" ? 0 : 1
          scale: root.fpGlyphScale
        }
      }
    }

    // Destello del borde (verde al confirmar, rojo al rechazar). Declarado
    // después del campo para quedar encima, y comparte su sacudida.
    Rectangle {
      id: fieldFlash
      anchors.fill: inputField
      radius: Style.cornerRadius
      color: "transparent"
      border.width: root.outlineThickness
      border.color: root.fpColor
      opacity: root.fpFlash
      visible: root.fpFlash > 0.002
      transform: Translate { x: root.shakeX }
    }
  }
}
