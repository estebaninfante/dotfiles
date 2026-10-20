---
name: animaciones-quickshell
description: "La guía canónica para animar en este escritorio (Quickshell/Omarchy): qué primitiva usar, cómo copiarla sin pensar y cómo verificarla. Usala SIEMPRE que se cree o modifique un componente, pantalla, panel, lista o diálogo; cuando el usuario pida 'que no salte', 'que se sienta fluido', 'morph', 'que los elementos tengan continuidad', 'que no aparezca de golpe', 'estilo pulido'; o cuando haya que auditar animaciones existentes. El motor y sus tokens viven en ~/.config/omarchy/motion (Tokens, Reveal, Stagger, Morph, Frames); los dibujos de puntos, en el skill animaciones-morph."
---

# Animar en este escritorio

El movimiento no decora: **explica qué pasó y de dónde vino**. Si no aclara
nada, no va. Y no se escribe a mano: se elige una primitiva y se le pasan datos.

Regla dura: **ningún componente nuevo escribe una duración, una curva ni un
delay**. Si te encontrás escribiendo `duration: 140`, pará: hay un token o una
primitiva para eso.

## Qué hay (y dónde)

Motor: `~/.config/omarchy/motion/` (versionado en dotfiles; cada consumidor
tiene una copia en `motion/` porque Quickshell no permite importar hacia
arriba).

| Pieza | Para qué |
| --- | --- |
| `Tokens` (singleton) | duraciones, curvas, resortes, `reduced`, alias por intención |
| `Reveal` | **todo lo que aparece o desaparece**, pareado y sin cortes |
| `Stagger` | barrido de un grupo, con dirección y tope |
| `Morph` | N elementos que se transforman con una sola línea de tiempo |
| `Frames` | frames parejos al display para dibujos en canvas |
| `Motion.js` | matemática pura: `ease`, `lerp`, `stagger`, resortes |

Referencia viva: el laboratorio, `omarchy-shell shell summon eztvn.motion '{}'`.
Ahí están las cuatro primitivas funcionando, con botón "Lento" (4x) para mirar
de cerca. Si algo no se parece a eso, está mal.

## Elegí por lo que pasa, no por un número

| Lo que cambia | Primitiva | Código |
| --- | --- | --- |
| Aparece / desaparece un panel, fila, tarjeta | `Reveal` | `Reveal { shown: x }` |
| Entra una lista o una grilla | `Stagger` + `Reveal` | `delay: rows.delay(index)` |
| Se transforma una forma en otra (anillos↔filas, lista↔detalle dibujado) | `Morph` | `weight(i)` |
| Se relevan dos páginas | `Reveal` cruzado o morph de páginas | ver abajo |
| Hover, foco, presión | `Behavior` con `Tokens.hover` / `Tokens.press` | 3 líneas |
| Vuelve sola a su lugar (drag, snap) | `SpringAnimation` con los resortes del token | 6 líneas |
| Cambia un contenedor de tamaño | `Behavior on implicitHeight` con `Tokens.page` | ver abajo |
| Dibujo propio (puntos, ondas, partículas) | `Frames` + canvas | skill `animaciones-morph` |

Si dudás entre dos, elegí la de más arriba: la que conserva identidad gana
sobre la que anima propiedades sueltas.

## Las cuatro recetas

Copiables de [`assets/Recetas.qml`](assets/Recetas.qml) (archivo verificado que
carga). Todas asumen `import "motion"` — la copia vendorizada del motor al lado
del componente.

### 1. Aparece / desaparece

```qml
Reveal {
  anchors.fill: parent
  shown: panel.opened
  Card { anchors.fill: parent }
}
```

`Reveal` entra desde abajo y 0.97 de escala, sale más rápido al mismo lugar, y
**mantiene el contenido montado** (no perdés scroll, foco ni el estado de un
input). Nunca uses `visible: false` a mano para algo que se ve.

### 2. Lista que entra en barrido

```qml
Stagger { id: rows; count: lista.count; shown: panel.opened }

Repeater {
  model: lista
  delegate: Reveal {
    required property int index
    shown: rows.shown
    delay: rows.delay(index)
    duration: rows.duration
    Fila { anchors.fill: parent }
  }
}
```

`Stagger` ya trae: barrido hacia adelante al abrir, hacia atrás al volver,
tope de 14 pasos, y 0 ms si las animaciones están apagadas. No calcules delays
a mano.

### 3. Morph de una forma a otra

```qml
Morph {
  id: morph
  count: filas.length
  onTick: function(now) {
    for (var i = 0; i < filas.length; i++)
      filas[i].k = morph.weight(i)     // 0..1, con el barrido ya aplicado
  }
}
// soltar el dedo: morph.endDrag() asienta en la forma más cercana
```

`weight(i)` es el único número que un dibujo necesita saber. La matemática de
las proyecciones (círculo↔filas, etc.) está en `Motion.js` y en el skill
`animaciones-morph`.

### 4. Micro-feedback y resortes

```qml
Rectangle {
  color: hover.containsMouse ? Tokens.hoverColor : base
  Behavior on color { ColorAnimation { duration: Tokens.hover } }
}

SpringAnimation on x {
  spring: Tokens.springStiffness
  damping: Tokens.springDamping
  mass: Tokens.springMass
  epsilon: Tokens.springEpsilon
}
```

## Tokens por intención

Además de `Tokens.fast/base/morph/slow`, hay alias semánticos. Usá estos:

| Alias | Valor | Cuándo |
| --- | --- | --- |
| `Tokens.hover` | fast | puntero encima, foco |
| `Tokens.press` | fast | la tecla/el click ya actuó |
| `Tokens.state` | base | cambia un estado chico (check, fila) |
| `Tokens.page` | morph | se releva una página o contenedor |
| `Tokens.surface` | slow | aparece una superficie completa |

Curvas: `Tokens.standard` (respuesta), `enter`, `exit`, `move` (morph),
`spring`, `draw` (canvas). Los valores viven en `motion.json`; cambiar el tempo
del escritorio es cambiar ese archivo.

## Páginas y persistencia

Dos páginas que se relevan se dejan **montadas** y se cruzan con `Reveal` (o con
el morph de páginas del skill viejo): destruirlas pierde scroll y foco.

```qml
Reveal { anchors.fill: parent; shown: !menu.inDetail; ServicesList {} }
Reveal { anchors.fill: parent; shown: menu.inDetail;  ServiceDetail {} }
```

El alto del contenedor sigue a la página activa con
`Behavior on implicitHeight { NumberAnimation { duration: Tokens.page; easing.type: Tokens.move } }`.
Cuidado: la página no debe tomar su `implicitHeight` de su propio `height`.

## Reduced motion: gratis

`Tokens` lee `~/.local/state/omarchy/animations-enabled`. Con `0`, **todas** las
duraciones son 0 y `Morph` asienta en el destino en el acto. No hay que
consultar nada por componente. Si escribís una animación fuera del motor, la
estás rompiendo.

## Rendimiento

- Animá `opacity`, `x`, `y`, `scale`, `rotation`: no disparan relayout.
- `Behavior on width/height` solo para el morph explícito de un contenedor.
- Un `Animation.Infinite` siempre con `running:` atado a visibilidad.
- Un `add: Transition` se dispara también cuando se **reasigna** el modelo
  (típico de un `Process` que hace poll): no lo uses si el modelo se recrea.
- Canvas con más de ~500 puntos: `renderStrategy` cooperativo + `Frames`;
  presupuesto ≤ 12 ms por frame.

## Gotas, blobs y formas orgánicas (leer antes de inventar)

La sensación "de gota" en UI de alto nivel viene de **tres cosas**, en este
orden: resortes interrumpibles, continuidad de la geometría (nunca saltar de
una forma a otra) y bordes suaves de verdad. No viene de un shader.

- Para una forma que se estira, se pega y vuelve: `SpringAnimation` con los
  resortes del token + un `Morph` para la geometría. Es lo que hace un "dynamic
  island".
- Para que dos formas **se fusionen** de verdad (metaballs) hace falta un
  *distance field* en shader. En Qt 6.11 los shaders de texto ya no existen:
  hay que compilar un `.qsb` con `qsb` y shipearlo. **No lo hagas sin medirlo en
  la pantalla real**: acá no se puede validar offscreen (no hay contexto GL) y
  un shader que compila puede costar 5-10 ms por frame en un panel chico.
- `QtQuick.Effects.MultiEffect` (blur + máscara con umbral) puede dar el gooey
  sin shader propio; sigue siendo GPU pura, misma advertencia.

Si el pedido es "que se sienta como una gota", empezá por resortes y
continuidad; el shader es el último recurso, no el primero.

## Verificación

1. **Motor** (obligatorio): `~/dotfiles/scripts/verify/motion.sh <carpeta>`.
   En archivos que ya usan el motor, falla con duraciones literales, sugiere el
   token, detecta `visible: false`, `Math.random()` en dibujo, `Behavior on
   width/height` y latidos sin guarda. También corre el test determinista de la
   línea de tiempo.
2. **Doble animación**: `scripts/verificar-animaciones.sh <carpeta>` del skill
   (Behavior + Transition sobre la misma propiedad, etc.).
3. **Sintaxis**: `qmllint -I /usr/share/omarchy/shell archivo.qml`.
4. **Visual**: el laboratorio (`eztvn.motion`) con "Lento" activado. Si no se
   parece a lo que hay ahí, no está listo.
5. **En vivo**: los plugins locales recargan al guardar. Pedile al usuario que
   abra el panel real: hay gestos que no se pueden disparar por script.

## Checklist

- [ ] Cada cosa que aparece o desaparece pasa por `Reveal`.
- [ ] Los grupos usan `Stagger` (no delays a mano).
- [ ] Ninguna duración/curva literal: tokens o primitivas.
- [ ] Nada se destruye y se recrea perdiendo scroll o foco.
- [ ] Con animaciones apagadas, todo cambia al instante y sigue usable.
- [ ] `verify/motion.sh` en verde y mirado en el laboratorio.
