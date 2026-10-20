# Motor de movimiento

Objetivo: que el escritorio se mueva como una pieza — morphs, persistencia,
nada que aparezca o se corte de golpe — y que cualquier widget futuro herede esa
calidad sin reimplementarla.

La tesis: **un motor de animación no es una biblioteca de curvas.** Es un modelo
de continuidad (quién es el mismo elemento antes y después), un reloj único por
gesto, un presupuesto de frame y un verificador que impide volver atrás.

## Las cinco primitivas

| Primitiva | Qué resuelve | Estado |
| --- | --- | --- |
| **Tokens** | una sola tabla de duraciones, curvas, escalonado, resortes y `reduced` | ✅ v1 |
| **Reveal** | aparición/desaparición pareada: nada entra ni sale de golpe | ✅ v1 |
| **Stagger** | un grupo entra en barrido, con dirección y con tope | ✅ v1 (en `Morph`/`Tokens.delayFor`) |
| **Morph** | N elementos se transforman con una sola línea de tiempo; drag + asentado | ✅ v1 |
| **Shared** | un elemento conserva identidad entre superficies (lista→detalle, panel→ventana) | ⏳ v2, con spike previo |

`Frames` y `Motion.js` son soporte: la primera alimenta dibujos en canvas de
forma pareja al display; el segundo es la matemática pura (ease, lerp,
escalonado, primavera).

## Archivos

```
manifest.json                 # plugin "eztvn.motion" (el laboratorio)
MotionLab.qml                 # ventana
Lab.qml                       # los cuatro demos + interruptor maestro
motion/                       # ← copia vendorizada del motor
  motion.json                 # única fuente de tokens
  qmldir
  Tokens.qml                  # singleton: lee motion.json y el interruptor
  Reveal.qml
  Morph.qml
  Frames.qml
  Motion.js
```

La fuente canónica del motor es `~/.config/omarchy/motion/` (versionada en
`linux/config/omarchy/motion`). El directorio del plugin tiene una **copia**,
no un symlink.

### Por qué copiar y no importar

Quickshell resuelve los imports QML dentro del root de la configuración y
rechaza las rutas que suben de directorio:

```
import "../../motion"   →  Reveal is not a type
import "motion"         →  ok (subdirectorio)
```

Un symlink que apunta afuera falla igual. Por eso el motor se vendoriza en cada
consumidor con `scripts/motion-vendor.sh`, y `scripts/verify/motion.sh` falla si
una copia se desvía de la fuente.

## Cómo se usa

### Todo lo que aparece o desaparece

```qml
// Antes: visible: panel.opened   (corte)
// Ahora:
Reveal {
  anchors.fill: parent
  shown: panel.opened
  delay: Tokens.delayFor(i)          // 0, 28, 56… con tope
  Card { anchors.fill: parent }      // el contenido sigue montado
}
```

`Reveal` entra desde abajo y 0.97 de escala (`reveal.rise` / `reveal.fromScale`
en `motion.json`), sale más rápido hacia el mismo lugar, y mantiene el contenido
vivo para no perder scroll ni foco.

### Un grupo entra en barrido

```qml
Repeater {
  model: filas
  delegate: Reveal {
    required property int index
    shown: lista.visible
    delay: Tokens.delayFor(lista.backward ? filas - 1 - index : index)
    Fila {}
  }
}
```

Al abrir entra 0,1,2…; al volver, al revés. Así el gesto barre en el sentido
del contenido y no vuelve sobre sus pasos.

### Un morph

```qml
Morph {
  id: morph
  count: 6
  onTick: function(now) {
    for (var i = 0; i < 6; i++) fila[i].k = morph.weight(i)   // 0..1 con barrido
  }
}
// abrir/cerrar:
onClicked: morph.go(1 - morph.progress)
// o arrastrar:
onPositionChanged: if (drag) morph.dragTo(dx / 240)
onReleased: morph.endDrag()          // asienta en la forma más cercana, sin escalonar
```

`weight(i)` es el peso del ítem i: la misma matemática para mover ítems (x, y,
escala) o para proyectar puntos en un canvas (ver skill `animaciones-morph`).

### Resortes

```qml
SpringAnimation on offset {
  spring: Tokens.springStiffness
  damping: Tokens.springDamping
  mass: Tokens.springMass
  epsilon: Tokens.springEpsilon
}
```

La física es del sistema, no de cada widget: los parámetros salen de
`motion.json`.

## Interruptor maestro

`~/.local/state/omarchy/animations-enabled` = `1`/`0`. `Tokens` lo observa y
pone todas las duraciones en 0; `Morph.calm` además hace que un cambio pedido a
mitad de un morph asiente en el destino en el acto. El laboratorio lo prende y
lo apaga de verdad (`hyprctl eval` incluido), así que es el lugar para probar
que la UI sigue siendo usable sin animaciones.

## Verificación

```bash
scripts/motion-vendor.sh                  # copia el motor a los consumidores
scripts/verify/motion.sh                  # tokens, copias, lint y línea de tiempo
scripts/verify/motion.sh bar/modules      # sólo una carpeta
```

- **Lint**: prohíbe duraciones literales (`duration: 260`) fuera del motor,
  `Math.random()` en animación, `visible: false` a mano, animar width/height y
  latidos infinitos sin guarda.
- **Copias**: hash idéntico a la fuente.
- **Línea de tiempo** (`scripts/verify/motion-timeline.qml`): test determinista
  de `Morph.advance()` — escalonado hacia adelante, barrido inverso, `calm`
  instantáneo, stall largo que asienta, drag y asentado. Sin render, sin flakiness.
- **Laboratorio**: `omarchy-shell shell summon eztvn.motion '{}'`. Es el criterio
  visual: los cuatro patrones, botón "Lento" (4x) para mirar de cerca y el
  interruptor real.

Presupuesto: **≤ 12 ms por frame** para morphs dibujados en canvas (medido con
`scripts/bench.py` de la skill `animaciones-morph`); los morphs de ítems son
GPU y no tienen presupuesto propio.

## Adopción

Estado al crear el motor: `scripts/verify/motion.sh` encuentra **38 duraciones
literales** en plugins existentes. Ese es el backlog de migración, por orden de
impacto visual:

1. `eztvn.osd` (volumen/brillo: se ve todo el tiempo).
2. `eztvn.lanmouse` (panel y filas).
3. `eztvn.hypr-outline` (nodo radial).
4. `eztvn.tmux` (sección de sesiones).
5. `bar/modules/ServicesMenu` (ya migrado a tokens vía el shim `Motion.qml`;
   falta que las páginas usen `Reveal` en vez de `visible`).

No migrar todo de una: cada archivo que se toca se verifica con
`scripts/verify/motion.sh <carpeta>` y se mira en el laboratorio.

## v2: persistencia entre superficies (Shared)

Un elemento (una fila, un ícono, un título) que viaja de una lista a un detalle
conserva su geometría: el ojo sigue el objeto en vez de ver dos apariciones.

Antes de escribirlo hay que resolver el riesgo real: en Wayland/Hyprland una
superficie no puede dibujar encima de otra con precisión de píxel sin un overlay
`layer-shell`, y el compositor ya anima ventanas por su cuenta. Por eso v1 no lo
incluye.

Spike de un día (criterio de corte):

- una ventana `layer-shell` transparente que siga un rectángulo dado;
- medir deriva con escalado fraccional y multi-monitor;
- si deriva > 1 px, parpadea, o pelea con la animación de ventanas de Hyprland,
  la primitiva se limita a morphs intra-superficie y se documenta el porqué.

## Decisiones y riesgos aceptados

- **Sin codegen**: `motion.json` lo leen el QML y (cuando haga falta) un export a
  CSS de 20 líneas. Una sola fuente, cero build step.
- **Sin reloj global**: cada `Morph` tiene su línea de tiempo; `Frames` sólo
  alimenta dibujos que lo necesitan. Un reloj global es una invitación a animar
  cosas que no lo piden.
- **Ítems antes que canvas**: el morph de la v1 mueve ítems (GPU). El canvas se
  reserva para dibujos que no existen como ítems.
- **Cross-window postergado** hasta el spike (arriba).
- **El verificador de timing es local, no de CI**: mide esta máquina, a este
  dpr. El gate duro es el lint + la línea de tiempo determinista.
