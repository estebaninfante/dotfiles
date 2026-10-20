.pragma library

// Destilado de omarchy-machine-mark (MIT, © Erik R. Johansson):
// https://github.com/erikrjohansson/omarchy-machine-mark/blob/main/Sigil.js
//
// Núcleo de un morph de puntos: un modelo, dos proyecciones, y un peso por
// elemento que interpola entre las dos. Nada de acá sabe qué se está
// dibujando; los "marks" son datos y el llamador los arma.

var TAU = Math.PI * 2

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
function lerp(a, b, k) { return a + (b - a) * k }
function ease(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2 }
function easeOut(x) { return 1 - Math.pow(1 - x, 3) }

// Peso de un elemento en un morph escalonado: `i` es su turno en la cola,
// `delay` la separación entre turnos y `dur` lo que tarda cada uno.
// t, t0 en ms.
function stagger(t, t0, i, dur, delay) { return ease(clamp((t - t0 - i * (delay || 0)) / dur, 0, 1)) }

// ------------------------------------------------------------------ azar con memoria
// Misma semilla, misma forma: un morph no puede barajar el dibujo entre frames
// ni entre aperturas. FNV-1a + mulberry32.
function hashStr(s) {
    var h = 2166136261 >>> 0
    for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0 }
    return h
}
function rng(seed) {
    var a = seed >>> 0
    return function() {
        a = (a + 0x6D2B79F5) >>> 0
        var t = a
        t = Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

// ------------------------------------------------------------------ proyecciones
// Una proyección es una función P(u, w, o) -> [x, y]. `u` corre a lo largo de
// la forma (0..1), `w` la cruza (-1 interior/abajo, 1 exterior/arriba). El
// tercer argumento es un array de salida reusado: una frame proyecta miles de
// puntos y crear un array por punto mantiene ocupado al recolector.
// Sin `o` devuelve un array nuevo (para uso suelto, no para frames).

function circle(cx, cy, R, r0, r1, turns) {
    return function(u, w, o) {
        var r = R * (r0 + (r1 - r0) * (w + 1) / 2), th = -Math.PI / 2 + TAU * (u + (turns || 0))
        o = o || [0, 0]
        o[0] = cx + Math.cos(th) * r; o[1] = cy + Math.sin(th) * r
        return o
    }
}
// Filas rectas: el otro extremo del morph.
function rows(x0, x1, y, rh) {
    return function(u, w, o) { o = o || [0, 0]; o[0] = x0 + u * (x1 - x0); o[1] = y - w * rh * 0.36; return o }
}
// El morph: la mezcla de las dos. wc = 1 es círculo, 0 es fila.
// Construila una vez por frame y elemento, no por punto.
function mixProj(PL, PC, wc) {
    if (wc >= 1) return PC
    if (wc <= 0) return PL
    var a = [0, 0], b = [0, 0]
    return function(u, w, o) {
        PL(u, w, a); PC(u, w, b)
        o = o || [0, 0]
        o[0] = a[0] * (1 - wc) + b[0] * wc
        o[1] = a[1] * (1 - wc) + b[1] * wc
        return o
    }
}

// ------------------------------------------------------------------ los puntos
// Todo mark se dibuja como puntos redondos. Un trazo se vuelve una tira de
// puntos parejos; más grueso = puntos más grandes y más separados.
var BEAD = { gap: 4.2, dashGap: 1.7, dashAlpha: 0.85, tiny: 1.1, round: 1.9 }
// Un frame de morph llena ~2000 puntos. Cada uno por separado: un solo path
// con todos costaba el doble de rasterizar. Los más chicos (1-2 px) son
// cuadrados de la misma área, los medianos octógonos, sólo los grandes
// círculos de verdad.
var OCT = [1, 0, 0.7071, 0.7071, 0, 1, -0.7071, 0.7071, -1, 0, -0.7071, -0.7071, 0, -1, 0.7071, -0.7071]
function beadDot(c, x, y, r) {
    if (r <= BEAD.tiny) { var h = r * 0.886; c.fillRect(x - h, y - h, 2 * h, 2 * h); return }
    c.beginPath()
    if (r > BEAD.round) c.arc(x, y, r, 0, TAU, false)
    else {
        c.moveTo(x + r, y)
        for (var k = 2; k < 16; k += 2) c.lineTo(x + OCT[k] * r, y + OCT[k + 1] * r)
        c.fill(); return
    }
    c.fill()
}
// Puntos de (u0,w0) a (u1,w1). `skipFirst` cuando sigue un tramo ya dibujado,
// `skipLast` cuando aterriza sobre su propio arranque (un anillo cerrado):
// un punto dibujado dos veces en un color con alfa se ve más oscuro.
function beadRun(c, P, u0, w0, u1, w1, step, r, skipFirst, skipLast) {
    var o = P(u0, w0, QA), px = o[0], py = o[1], L = 0, k = Math.abs(u1 - u0) > 1e-6 ? 8 : 1, q
    for (q = 1; q <= k; q++) {
        o = P(u0 + (u1 - u0) * q / k, w0 + (w1 - w0) * q / k, QA)
        L += Math.sqrt((o[0] - px) * (o[0] - px) + (o[1] - py) * (o[1] - py)); px = o[0]; py = o[1]
    }
    if (L < step * 0.6) {
        if (!skipFirst) { o = P((u0 + u1) / 2, (w0 + w1) / 2, QA); beadDot(c, o[0], o[1], r) }
        return
    }
    var n = Math.max(1, Math.round(L / step))
    for (q = skipFirst ? 1 : 0; q <= (skipLast && n > 1 ? n - 1 : n); q++) {
        o = P(u0 + (u1 - u0) * q / n, w0 + (w1 - w0) * q / n, QA)
        beadDot(c, o[0], o[1], r)
    }
}
function closes(P, u0, w0, u1, w1) {
    var a = P(u0, w0, QB), ax = a[0], ay = a[1]
    a = P(u1, w1, QB)
    return Math.abs(a[0] - ax) + Math.abs(a[1] - ay) < 0.5
}
var QA = [0, 0], QB = [0, 0]

function sameBead(a, b) {
    return a.col === b.col && (a.a === undefined ? 1 : a.a) === (b.a === undefined ? 1 : b.a) && !a.dash === !b.dash
}
// marks: [{ d: "tick"|"seg"|"dot", u|u0,u1, w|w0,w1, lw, s, col, a, dash }]
// Los marks con la misma apariencia se dibujan seguidos: cambiar fillStyle o
// globalAlpha por punto es lo que más encarece un frame.
function drawBeads(c, ms, P, z) {
    var ga = c.globalAlpha, i = 0
    while (i < ms.length) {
        var m = ms[i], end = i + 1
        while (end < ms.length && sameBead(m, ms[end])) end++
        c.globalAlpha = ga * (m.a === undefined ? 1 : m.a) * (m.dash ? BEAD.dashAlpha : 1)
        c.fillStyle = m.col
        for (var j = i; j < end; j++) {
            var mk = ms[j]
            if (mk.d === "dot") {
                var o = P(mk.u, mk.w, QA)
                beadDot(c, o[0], o[1], Math.max(0.9, mk.s * z * 0.8))
                continue
            }
            var r = clamp(mk.lw * z * 0.5, 0.8, 2.6), step = Math.max(BEAD.gap, r * 2.7) * (mk.dash ? BEAD.dashGap : 1)
            if (mk.d === "tick") beadRun(c, P, mk.u, mk.w0, mk.u, mk.w1, step, r, false, false)
            else beadRun(c, P, mk.u0, mk.w, mk.u1, mk.w, step, r, false, closes(P, mk.u0, mk.w, mk.u1, mk.w))
        }
        i = end
    }
    c.globalAlpha = ga
}

// ------------------------------------------------------------------ color
function rgbOf(hex) { var n = parseInt(String(hex).slice(1, 7), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255] }
function alpha(hex, a) { var c = rgbOf(hex); return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + a + ")" }
function mix(h1, h2, k) {
    var a = rgbOf(h1), b = rgbOf(h2)
    return "#" + a.map(function(v, i) { return ("0" + Math.round(lerp(v, b[i], k)).toString(16)).slice(-2) }).join("")
}
