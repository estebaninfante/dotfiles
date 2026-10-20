import QtQuick
import "motion"

// Compatibilidad: los widgets que ya reciben `motion` por propiedad siguen
// funcionando, pero los valores salen del motor único (~/.config/omarchy/motion,
// tokens en motion.json). No hay una segunda tabla de duraciones.
//
// Código nuevo: importá "motion" y usá Tokens directamente, o mejor todavía
// usá Reveal / Morph.
QtObject {
  readonly property bool reduced: Tokens.reduced
  readonly property int fast: Tokens.fast
  readonly property int base: Tokens.base
  readonly property int morph: Tokens.morph
  readonly property int slow: Tokens.slow
  readonly property int stagger: Tokens.staggerStep
  readonly property int standard: Tokens.standard
  readonly property int enter: Tokens.enter
  readonly property int exit: Tokens.exit
  readonly property int move: Tokens.move
  readonly property int spring: Tokens.spring
}
