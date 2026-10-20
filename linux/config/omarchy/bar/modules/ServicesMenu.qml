import QtQuick
import qs.Commons
import qs.Ui

// Shell del menú de servicios. Mantiene una estética Omarchy (PanelHero,
// PanelSeparator, PanelSectionHeader, Button, Toggle) y enruta entre la lista
// de servicios y la vista de detalle de cada uno dentro de la misma ventana.
//
// Morph lista ↔ detalle:
// - Las dos páginas viven montadas (no se destruyen): la lista conserva su
//   scroll al volver del detalle.
// - El cambio es direccional y breve: la que sale se corre y se apaga, la que
//   entra llega desde el lado hacia donde va la navegación (detalle = derecha,
//   volver = izquierda), con cruce de opacidad.
// - El alto del contenedor (y con él el del popup) anima hacia la página
//   activa, así el panel "crece" y "se encoge" en lugar de saltar.
// Las duraciones y curvas salen de Motion (una sola fuente de verdad).
Item {
  id: menu

  property var module
  property var motion

  readonly property bool open: module ? module.menuOpen : false
  readonly property bool inDetail: module ? module.inDetail : false
  readonly property color fg: module ? module.fg : Color.foreground
  readonly property color dim: module ? module.dim : Color.muted
  readonly property color unknown: module ? module.unknownColor : Color.muted
  readonly property color globalColor: module ? module.globalColor : Color.muted
  readonly property string fontFamily: module ? module.fontFamily : Style.font.family

  readonly property int dur: motion ? motion.morph : 260
  readonly property int ease: motion ? motion.move : Easing.InOutCubic
  // Cuánto se desplaza una página al entrar/salir. Corto a propósito: se lee
  // como continuidad, no como un carrusel.
  readonly property int drift: Style.space(18)

  implicitWidth: Style.space(400)
  implicitHeight: stage.implicitHeight
  anchors.fill: parent

  // Alto del contenedor: acompaña a la página activa.
  Behavior on implicitHeight {
    NumberAnimation { duration: menu.dur; easing.type: menu.ease }
  }

  // Entrada de la superficie al abrir (independiente del morph interno).
  opacity: 0
  y: -Style.space(5)
  states: [
    State {
      name: "shown"
      when: menu.open
      PropertyChanges { target: menu; opacity: 1; y: 0 }
    }
  ]
  transitions: Transition {
    NumberAnimation {
      properties: "opacity,y"
      duration: menu.motion ? menu.motion.base : 180
      easing.type: menu.motion ? menu.motion.standard : Easing.OutCubic
    }
  }

  Item {
    id: stage
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: menu.implicitHeight
    implicitHeight: menu.inDetail ? detailPage.implicitHeight : listPage.implicitHeight
    clip: true

    ServicesList {
      id: listPage
      width: stage.width
      height: stage.height
      module: menu.module
      motion: menu.motion
      opacity: 1
      enabled: opacity > 0.5
      visible: opacity > 0.001
      onOpenRequested: function(svc) { if (menu.module) menu.module.openDetail(svc) }
    }

    ServiceDetail {
      id: detailPage
      width: stage.width
      height: stage.height
      module: menu.module
      motion: menu.motion
      opacity: 0
      enabled: opacity > 0.5
      visible: opacity > 0.001
      onConfirmRequested: function(action, message, second) {
        menu.requestConfirm(action, message, second)
      }
    }

    states: [
      State {
        name: "list"
        when: !menu.inDetail
        PropertyChanges { target: listPage; opacity: 1; x: 0 }
        PropertyChanges { target: detailPage; opacity: 0; x: menu.drift }
      },
      State {
        name: "detail"
        when: menu.inDetail
        PropertyChanges { target: listPage; opacity: 0; x: -menu.drift }
        PropertyChanges { target: detailPage; opacity: 1; x: 0 }
      }
    ]

    transitions: Transition {
      NumberAnimation {
        properties: "x,opacity"
        duration: menu.dur
        easing.type: menu.ease
      }
    }
  }

  // --- Confirmación modal compartida -------------------------------------
  // La usan los submenús específicos (hypr-remote) para acciones destructivas.

  property string pendingAction: ""
  property string pendingSecondMessage: ""

  function requestConfirm(action, message, second) {
    menu.pendingAction = String(action || "")
    menu.pendingSecondMessage = String(second || "")
    confirmDialog.message = String(message || "")
    confirmDialog.selectedIndex = 1
    confirmDialog.opened = true
  }

  function resolveConfirm() {
    if (menu.pendingSecondMessage.length > 0) {
      confirmDialog.message = menu.pendingSecondMessage
      confirmDialog.selectedIndex = 1
      menu.pendingSecondMessage = ""
      return
    }

    var action = menu.pendingAction
    menu.pendingAction = ""
    confirmDialog.opened = false

    // La página de detalle está siempre montada: no hay Loader que consultar.
    if (detailPage.handleConfirmed) detailPage.handleConfirmed(action)
  }

  ConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    background: Color.popups.background
    foreground: menu.fg
    scrim: Util.alpha(Color.popups.background, 0.72)
    fontFamily: menu.fontFamily

    onCanceled: {
      opened = false
      menu.pendingAction = ""
      menu.pendingSecondMessage = ""
    }
    onConfirmed: menu.resolveConfirm()
  }
}
