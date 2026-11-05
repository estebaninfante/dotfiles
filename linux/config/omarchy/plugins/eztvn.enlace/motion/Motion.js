// Matemática pura de movimiento. Sin QML, sin estado: se importa desde
// cualquier componente (`import "../motion/Motion.js" as M`).
//
// Los valores por defecto espejan motion.json; lo que manda es Tokens.qml.
// Acá sólo viven las funciones que no necesitan leer tokens.

var TAU = Math.PI * 2

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
function lerp(a, b, k) { return a + (b - a) * k }

// In-out cúbica: la curva de las transformaciones (morph, secciones).
function ease(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2 }
function easeOut(x) { return 1 - Math.pow(1 - x, 3) }
function easeIn(x) { return x * x * x }

// Peso de un ítem en una entrada/morph escalonado. `t` y `t0` en ms.
function stagger(t, t0, i, dur, step, max) {
  var d = Math.min(i, max === undefined ? 999 : max) * (step || 0)
  return ease(clamp((t - t0 - d) / Math.max(1, dur), 0, 1))
}

// Orden de barrido: al ir hacia adelante entra 0,1,2…; al volver, al revés.
// Así el gesto siempre "barre" en la dirección del contenido y nunca vuelve
// sobre sus pasos.
function order(i, n, backward) { return backward ? n - 1 - i : i }

// Posición de una página que entra/sale con deriva lateral (list ↔ detail).
function drift(k, from, to, px) { return lerp(from ? px : -px, to ? px : 0, k) }

// Primavera crítica/subcrítica en forma de progreso 0..1. Para casos donde no
// se puede usar SpringAnimation (canvas, JS). `v` es la velocidad normalizada.
function springStep(x, v, target, damping, stiffness, mass, dt) {
  var a = (-stiffness * (x - target) - damping * v) / Math.max(0.001, mass)
  v += a * dt
  x += v * dt
  return [x, v]
}
