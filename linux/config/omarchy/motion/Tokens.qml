pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Motion.js" as M

// Tokens de movimiento: la única fuente de verdad.
//
// Se leen de ~/.config/omarchy/motion/motion.json (versionado en dotfiles) y se
// re-leen si cambia. Cada consumidor tiene su instancia (import relativo), que
// es barata: el archivo pesa nada y el FileView se reusa.
//
// Regla: ningún componente escribe duraciones ni curvas literales. Usa
// Tokens.dur("fast"), Tokens.enter, Tokens.fast, Tokens.staggerStep...
// Con animaciones apagadas todo cae a 0 y la UI cambia al instante.
QtObject {
  id: t

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/motion/motion.json"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/animations-enabled"

  // Defaults: si el JSON falta o está roto, el motor igual funciona.
  property var data: ({
    duration: { instant: 0, fast: 120, base: 180, morph: 260, slow: 340, draw: 820 },
    stagger: { step: 28, stepMorph: 40, max: 14 },
    curve: { standard: "OutCubic", enter: "OutQuint", exit: "InCubic",
             move: "InOutCubic", spring: "OutBack", draw: "InOutCubic" },
    spring: { damping: 0.72, mass: 1.0, stiffness: 4.2, epsilon: 0.01 },
    reveal: { rise: 6, fromScale: 0.97 },
    drift: 18
  })

  property bool reduced: false
  // Multiplicador para inspeccionar el movimiento (laboratorio): 0.25 = 4x
  // más lento. No lo toca la UI de producción.
  property real speed: 1

  readonly property var curves: ({
    Linear: Easing.Linear,
    OutQuad: Easing.OutQuad, InQuad: Easing.InQuad, InOutQuad: Easing.InOutQuad,
    OutCubic: Easing.OutCubic, InCubic: Easing.InCubic, InOutCubic: Easing.InOutCubic,
    OutQuint: Easing.OutQuint, InQuint: Easing.InQuint, InOutQuint: Easing.InOutQuint,
    OutBack: Easing.OutBack, InBack: Easing.InBack,
    OutExpo: Easing.OutExpo, InExpo: Easing.InExpo, InOutExpo: Easing.InOutExpo
  })

  function num(group, key, fallback) {
    var g = data && data[group]
    var v = g ? Number(g[key]) : NaN
    return isFinite(v) ? v : fallback
  }
  function curveOf(key) {
    var name = data && data.curve ? data.curve[key] : ""
    return curves[name] !== undefined ? curves[name] : Easing.OutCubic
  }

  // Duración efectiva en ms: 0 si el usuario apagó las animaciones.
  function dur(key) {
    if (reduced) return 0
    return Math.max(0, Math.round(num("duration", key, 180) * speed))
  }
  function durRaw(key) { return num("duration", key, 180) }

  readonly property int instant: dur("instant")
  readonly property int fast: dur("fast")
  readonly property int base: dur("base")
  readonly property int morph: dur("morph")
  readonly property int slow: dur("slow")
  readonly property int draw: dur("draw")

  readonly property int standard: curveOf("standard")
  readonly property int enter: curveOf("enter")
  readonly property int exit: curveOf("exit")
  readonly property int move: curveOf("move")
  readonly property int spring: curveOf("spring")
  readonly property int drawCurve: curveOf("draw")

  readonly property int staggerStep: reduced ? 0 : Math.round(num("stagger", "step", 28) * speed)
  readonly property int staggerStepMorph: reduced ? 0 : Math.round(num("stagger", "stepMorph", 40) * speed)
  readonly property int staggerMax: Math.round(num("stagger", "max", 14))

  readonly property real revealRise: num("reveal", "rise", 6)
  readonly property real revealFrom: num("reveal", "fromScale", 0.97)
  readonly property real drift: data && isFinite(Number(data.drift)) ? Number(data.drift) : 18
  readonly property real springDamping: num("spring", "damping", 0.72)
  readonly property real springStiffness: num("spring", "stiffness", 4.2)
  readonly property real springMass: num("spring", "mass", 1.0)
  readonly property real springEpsilon: num("spring", "epsilon", 0.01)

  // Un delay escalonado, con tope: nunca una entrada de 3 segundos.
  function delayFor(i, step) {
    if (reduced) return 0
    return Math.min(i, staggerMax) * Math.round((step === undefined ? staggerStep : step))
  }

  // Un QtObject no tiene propiedad default: los FileView viven en propiedades.
  readonly property FileView configFile: FileView {
    path: t.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var v = JSON.parse(text())
        if (v && v.duration) t.data = v
      } catch (e) {}
    }
    onFileChanged: reload()
  }

  readonly property FileView stateFile: FileView {
    path: t.statePath
    watchChanges: true
    printErrors: false
    onLoaded: t.reduced = text().trim() === "0"
    onLoadFailed: t.reduced = false
    onFileChanged: reload()
  }
}
