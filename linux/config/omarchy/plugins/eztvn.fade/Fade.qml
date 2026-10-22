import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "motion"

// Cortina negra a pantalla completa.
//
// Existe para tapar el hueco negro que deja el panel OLED cuando Hyprland
// re-aplica el modo (60Hz en ahorro, 120Hz en rendimiento): ese modeset tarda
// unas décimas y sin cortina se ve como un apagón seco. Acá se baja a negro
// con el motor de movimiento del escritorio, se hace el cambio mientras la
// pantalla ya está negra, y se vuelve.
//
// No decide cuándo: el guion de energía (`pantalla-fade`) llama `out`, corre el
// cambio y llama `in`. Así el que sabe cuánto tarda el cambio es el guion, y
// acá solo vive la animación.
//
// En OLED el negro puro apaga los píxeles: el fundido se siente como si la
// pantalla se apagara despacio, no como un flash.
Item {
  id: root

  // 0 = descubierto, 1 = negro pleno.
  property real cover: 0

  // Duraciones: salen del motor. El guion puede pasarlas explícitas para que
  // su espera coincida al milisegundo con la animación real.
  property int outMs: Tokens.base
  property int inMs: Tokens.morph

  readonly property bool covered: root.cover > 0.999
  readonly property bool busy: outAnimation.running || inAnimation.running

  function out(ms) {
    var requested = parseInt(String(ms), 10)
    // Con animaciones apagadas (reduced) el fundido no existe: negro seco.
    root.outMs = Tokens.reduced ? 0 : ((isFinite(requested) && requested > 0) ? requested : Tokens.base)
    inAnimation.stop()
    outAnimation.restart()
  }

  function into(ms) {
    var requested = parseInt(String(ms), 10)
    root.inMs = Tokens.reduced ? 0 : ((isFinite(requested) && requested > 0) ? requested : Tokens.morph)
    outAnimation.stop()
    inAnimation.restart()
  }

  // Para cortar en seco (tests, o si el guion murió a mitad de camino).
  function reset() {
    outAnimation.stop()
    inAnimation.stop()
    root.cover = 0
  }

  NumberAnimation {
    id: outAnimation
    target: root
    property: "cover"
    to: 1
    duration: root.outMs
    easing.type: Tokens.enter
  }

  NumberAnimation {
    id: inAnimation
    target: root
    property: "cover"
    to: 0
    duration: root.inMs
    easing.type: Tokens.exit
  }

  IpcHandler {
    target: "eztvn.fade"

    function blackout(ms: string): string { root.out(ms); return "ok" }
    function uncover(ms: string): string { root.into(ms); return "ok" }
    function resetCover(): string { root.reset(); return "ok" }
    function phase(): string { return root.covered ? "covered" : (root.cover > 0 ? "moving" : "open") }
    function ping(): string { return "ok" }
  }

  // Red de seguridad: si el que pidió el negro murió a mitad de camino, no
  // dejar la pantalla tapada. En uso normal el negro dura <1s y el timer no
  // llega a dispararse.
  Timer {
    interval: 3000
    running: root.cover > 0.001
    onTriggered: root.into()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData

      screen: modelData
      // Siempre mapeada: una superficie estática y transparente no daña ni
      // cuesta frames, y garantiza que el negro esté listo antes del modeset
      // (mapear justo en el cambio agregaría un frame de retraso).
      visible: true
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-fade"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Sin región de entrada: la cortina nunca se come un click.
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.cover
      }
    }
  }
}
