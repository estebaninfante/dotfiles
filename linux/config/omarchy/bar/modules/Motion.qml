import QtQuick
import Quickshell
import Quickshell.Io

// Tokens de movimiento del shell.
//
// Una sola fuente de verdad para duraciones, curvas y escalonado. Los
// componentes NO escriben números sueltos: usan `motion.fast`, `motion.morph`,
// `motion.move`, etc. Así todo el escritorio se siente de la misma familia y
// cambiar el ritmo es tocar un archivo.
//
// Respeta el interruptor maestro de animaciones (plugin `eztvn.animations`,
// estado en ~/.local/state/omarchy/animations-enabled): si está desactivado,
// todas las duraciones caen a 0 y la UI cambia sin desplazarse.
//
// Uso: instanciar UNA vez en la raíz del widget y pasarlo a los hijos
//   Motion { id: motion }
//   Servicio { motion: motion }
QtObject {
  id: root

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/animations-enabled"

  // true = el usuario apagó las animaciones: duraciones 0.
  property bool reduced: false

  // --- Duraciones (ms) -----------------------------------------------------
  // La escala es deliberadamente corta: son micro-interacciones de escritorio,
  // no una presentación. Más de ~300 ms se siente lento y tapa el contenido.

  readonly property int fast: reduced ? 0 : 120     // color, hover, presión
  readonly property int base: reduced ? 0 : 180     // estado chico, filas
  readonly property int morph: reduced ? 0 : 260    // contenedor y páginas
  readonly property int slow: reduced ? 0 : 340     // superficie completa
  readonly property int stagger: reduced ? 0 : 28   // retraso por ítem

  // --- Curvas --------------------------------------------------------------
  // standard: respuesta inmediata a una acción del usuario.
  // enter:    lo que aparece desde cero (superficies, páginas).
  // exit:     lo que se va; arranca rápido y se desacelera al final.
  // move:     lo que cambia de lugar o de tamaño (morph, reacomodo).
  // spring:   para expandir/crecer con un rebote corto. Usar con moderación.
  readonly property int standard: Easing.OutCubic
  readonly property int enter: Easing.OutQuint
  readonly property int exit: Easing.InCubic
  readonly property int move: Easing.InOutCubic
  readonly property int spring: Easing.OutBack

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.reduced = text().trim() === "0"
    onLoadFailed: root.reduced = false
    onFileChanged: reload()
  }
}
