---
name: animaciones-morph
description: "Diseñar y construir un morph continuo hecho de puntos (una forma que se transforma en otra) en Quickshell/Omarchy, o auditar uno existente. Usala cuando el usuario pida algo que se transforme, se despliegue o se 'amase' (un gráfico que se vuelve lista, un anillo que se vuelve filas, un logo que se reordena), cuando quiera 'esas animaciones tan lindas' de puntos/beads, o cuando una animación de canvas se sienta cortada, temblorosa, lenta en pantallas de 120 Hz, o cueste 30 ms por frame. Cubre un modelo con dos proyecciones, dos motores (capas en reposo + canvas de morph) con handover, pacing de refrescos, dibujo de puntos barato, siembra estable, color por tema, datos vivos y tres verificadores deterministas."
---

# Morph de puntos en Quickshell

Referencia viva: [`omarchy-machine-mark`](https://github.com/erikrjohansson/omarchy-machine-mark)
(MIT, © Erik R. Johansson) — el About de Omarchy como un sigilo de puntos que
se amasa en una tira de filas y vuelve. Léelo entero antes de tocar nada:
`Sigil.js` (modelo, proyecciones, dibujo), `AboutCard.qml` (los dos motores, el
handover, el pacing), `MachineMark.qml` (ventana y lecturas).

Para tokens, `Behavior`, morph de páginas, latidos y reduced motion seguí
además el skill `animaciones-quickshell`. Esto de acá es la capa de arriba:
lo que hace que una forma dibujada a mano se vea *bella* y no se sienta rota.

## Por qué se ve tan bien

No es un efecto. Son seis decisiones que se sostienen entre sí:

1. **Una sola forma, dos lecturas.** El dibujo no cambia de objeto al
   transformarse: cada elemento es el mismo punto en un modelo `(u, w)`
   proyectado de dos maneras. Nada nace ni muere, nada se cruza de golpe.
2. **Todos los elementos son el mismo material.** Un solo tipo de marca —
   puntos redondos — mide secciones, memoria, tiempo y pulsos. La unidad hace
   que 14 datos distintos parezcan un dibujo y no un dashboard.
3. **Escala por dato, no por decoración.** El tamaño, el largo y el grosor de
   cada punto salen del número que representa (un punto por núcleo, más grande
   la semana que más actualizaste). Cuando el dato crece se vuelve *más
   grueso* (una línea por cada 4 núcleos), no se amontona.
4. **Silencio en reposo.** Quieto, se mueve apenas: los anillos giran ~10 px
   por segundo. El movimiento es una deriva, no un show.
5. **Cada gesto tiene una causa y una dirección.** Arrastrar a la derecha
   desenrolla; soltar asienta en la forma más cercana. Click o Espacio amasan.
   Las flechas dicen lo mismo que los botones.
6. **Los datos son la identidad.** La forma la siembra el hostname + el
   hardware + la fecha de instalación: dos máquinas nunca tienen el mismo
   dibujo, y la tuya siempre tiene el mismo.

## La idea central: interpolar proyecciones, no objetos

```js
// Un elemento vive en (u, w): u corre a lo largo de la forma, w la cruza.
// círculo: u = ángulo, w = radio entre r0 y r1
// filas:   u = x,        w = altura dentro de la fila
var PL = Puntos.rows(x0, x1, y, rh)
var PC = Puntos.circle(cx, cy, R, r0, r1, turns)
var Pj = Puntos.mixProj(PL, PC, peso)   // peso 0 = filas, 1 = círculo
Puntos.drawBeads(c, marks, Pj, zoom)
```

Todo lo demás sale de ahí: el estado intermedio es una órbita que se abre. Un
morph hecho así **nunca se rompe** (los puntos viajan por el espacio, no hay
frames intermedios inválidos) y **no necesita dos dibujos que se crucen**.

Reglas:

- El peso es **por elemento**, no global: las 13 anillas no arrancan juntas.
- `u` y `w` son las mismas para las dos proyecciones. Si el modelo tiene que
  reordenarse, se reordena antes del morph, no durante.
- Las proyecciones se construyen una vez por frame y elemento. Nunca una
  función nueva por punto, ni un array nuevo por punto (ver `QA`/`QB` en
  `assets/Puntos.js`: reusar dos arrays de salida).
- El peso se puede manejar a mano: un drag de 240 px recorre la forma entera
  (`s = clamp(s0 - dx / 240, 0, 1)`), y la velocidad del dedo manda. Eso es lo
  que lo hace sentir "amasable".

## Dos motores y un solo handover

Un canvas que redibuja 2000 puntos por frame no puede estar corriendo siempre
(consume GPU y batería). Pero las capas quietas no pueden interpolar. Se usan
los dos, y el cambio no se nota:

| Momento | Qué dibuja |
| --- | --- |
| En reposo, forma A | Una `Layer` (Canvas) por anillo/fila, dibujada una vez, movida sólo con `rotation`. La estática (divisores, íconos, centro) en otra capa. |
| Morph / build-in | Un único `Canvas` del tamaño de la tarjeta, todo redibujado por frame. |
| Handover | Las capas nuevas se dibujan **debajo** del canvas; recién cuando la última avisó que pintó, el canvas se desvanece en 220 ms sobre ellas. Al empezar un morph, el canvas entra en 90 ms. |

Detalles que hacen la diferencia (todos están en `AboutCard.qml`):

- **Build numerado.** Cada pedido de dibujo lleva el número de la generación;
  `layerDone(id, gen)` ignora los avisos viejos. Sin eso, una capa lenta da por
  lista una tanda que no lo está y se ve el fondo.
- **Una capa por frame.** Pintarlas todas juntas congelaba un frame ~30 ms.
  `FrameAnimation` que saca una de la cola por tick.
- **Las capas se cachean por clave.** `layersKey()` = tamaño + dpr + fuente +
  colores + herencia del equipo. Si no cambió, no se redibuja: volver a la
  forma anterior es sólo un fade.
- **Snap a la grilla de píxeles.** `snap(v) = floor(v * dpr) / dpr` para que las
  capas caigan en los mismos píxeles que el canvas que reemplazan.
- **Fondo opaco en el canvas de morph** (el color de la ventana), para que las
  capas de abajo no se transparenten y dupliquen el trazo. En temas
  translúcidos (`background.a < 0.9`) no se puede: ahí se cruza en fade.
- **Las capas se cortan cuando la ventana se cierra** (`Loader { active: opened }`),
  y el canvas vive con `visible`/`running` atados al estado real.

## Frames: dibujar para el momento en que el frame se ve

`FrameAnimation` no dice cuándo cae el frame, sólo cuánto duró el anterior.
Si dibujás con "ahora", el frame llega un refresco tarde. Si dibujás tan rápido
como puedas, en 120 Hz caés entre refrescos y se ve stutter (frame corto +
doble frame cada ~140 ms, visible en una grabación a 60 fps).

`assets/Frames.qml` resuelve las dos cosas:

```qml
Frames { id: frames; running: card.morphing; onTick: function(t) { card.draw(t) } }
// t = clock + duración del frame: el momento en que ESTE frame va a estar arriba.
// En pantallas de más de 96 Hz descarta uno de cada dos refrescos.
// Math.max(clock + ms, lastT): el reloj nunca retrocede.
```

Y `t0` de una animación se fija **en el primer frame dibujado**, no cuando se
pidió (`if (anim.t0 < 0) anim.t0 = t`), para que un arranque lento no se coma
el principio del movimiento.

Presupuesto: **≤ 12 ms por frame de morph** medido con `scripts/bench.py`
(deja 4-6 ms para el resto del shell dentro de 16.7 ms). Medido en esta máquina
(Ryzen 7 7840HS): el About de referencia da 7.8 ms a 1.25×; el demo de
`assets/` con 13 anillos, 6.3 ms.

## Escalonado y curvas

```js
// Morph: 820 ms por elemento, arranques cada 40 ms, en orden.
// Al asentar un drag: 280 ms, sin escalonado (fast).
var k = Puntos.ease(clamp((t - t0 - i * 40) / 820, 0, 1))
// Build-in de apertura: 420 ms por anillo, 45 ms de separación.
var build = ease(clamp((t - builtAt - i * 45) / 420, 0, 1))
```

- `ease` = in-out cúbica (`x<0.5 ? 4x³ : 1-(-2x+2)³/2`). Una sola curva para
  todo el dibujo: nada de rebotes ni elásticos en algo que se amasa.
- **Escalonar sólo hacia un lado**: al ir a la forma B el orden es `i`, al
  volver es `n-1-i`. Así el gesto siempre "barre" en la misma dirección que el
  contenido.
- Un gesto rápido del usuario (drag) no se escalona: 280 ms, todos juntos. El
  escalonado es para lo que el sistema decide, no para lo que manda el dedo.
- Máximo ~14 elementos escalonados con 40 ms: 820 + 13×40 ≈ 1.35 s. Más que
  eso ya no se lee como una transformación, se lee como una espera.

## Dibujar puntos: lo que cuesta y lo que no

Todo esto está medido y comentado en `Sigil.js`; es la diferencia entre 3 ms y
30 ms por frame.

- **Un punto por path.** Un solo `beginPath()` con 2000 puntos costaba el doble
  que llenarlos de a uno (`~12 ms` vs `~3.5 ms` en offscreen 1.25×).
- **Tres calidades según el radio**: ≤1.1 px cuadrado del mismo área (~0.886 r),
  ≤1.9 px octógono, más grande círculo. Un punto de 1.5 px no se distingue de
  un círculo y el círculo cuesta.
- **Separación del punto según el grosor**: `step = max(4.2, r * 2.7)`; las
  líneas punteadas multiplican por 1.7. Si `L < step * 0.6` se dibuja un solo
  punto en el medio, no una tira de dos.
- **Un punto no se dibuja dos veces** si tiene alfa (`skipFirst` al continuar un
  tramo, `skipLast` cuando aterriza sobre el arranque de un anillo cerrado): se
  ve más oscuro. Y **cerrá el anillo**: si el último punto no coincide con el
  primero en 12 en punto, queda una muesca visible.
- **Agrupá por apariencia**: `drawBeads` junta los marks consecutivos con el
  mismo color/alfa/dash y cambia `fillStyle` una vez por grupo. Cambiarlo por
  punto es lo que más encarece un frame.
- **Cacheá los marks**: durante un morph los marks no cambian, sólo la
  proyección. Se arman una vez al empezar y se invalidan con una clave
  (color/tema, herencia del equipo, tamaño). Pero **no caches las posiciones**:
  ésas son justamente las que se interpolan.
- **Nada de `Math.random()` en el dibujo.** La forma se siembra una vez
  (`hashStr(hostname|cpu|gpu|instalación)` + `rng()` mulberry32). Si el azar
  corre por frame, el dibujo tiembla; si cambia entre aperturas, la máquina
  perdió su identidad.
- **Texto en items QML, no en el canvas**: `fillText` no respeta la fuente del
  sistema, no se puede elidir ni seleccionar. Se posiciona en JS
  (`textPos(layout, i, k)` devuelve `{nameX, valueX, y}`) y se interpola el
  mismo `k` que el resto. Las posiciones se recalculan por frame; el texto se
  re-mide cada 5 s como mucho.
- **El canvas a píxeles de dispositivo**: `width: Math.round(w * dpr)`,
  `scale: 1 / dpr`, `transformOrigin: TopLeft`. Si sólo agrandás el canvas,
  mostrás su esquina.

## Color desde el tema

- Un color por sección (`hw`, `sw`, `age`) y los anillos vecinos alternan con
  una mezcla al 32% con el foreground: se separan sin sumar colores nuevos.
- El dato activo va en `accent`; lo apagado es `mix(fg, bg, 0.34)` con alfa.
- En temas claros hay que compensar: los trazos finos (<1.45) engordan y los
  alfas altos se vuelven 1, porque los puntos llevan la mitad de la tinta de
  una línea sólida.
- El `colors.toml` del tema se lee con la misma regex que el shell
  (`^\s*([\w-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})`) y se relee al abrir y cuando
  cambia `theme.name`, porque un cambio de tema reemplaza la carpeta y el
  `FileView` no sobrevive. Ver skill `omarchy`.

## Datos vivos sin redibujar todo

- Lo que cambia lento (paquetes, temas, versiones) se lee al abrir.
- Lo vivo (memoria, uso de GPU, uptime) cada 4 s, y **sólo se redibuja la capa
  afectada**: redibujar las 14 capas son ~18 MB de imágenes y frena el giro.
- Los diales lentos (uptime, última actualización) se repintan una vez por
  minuto, no por segundo; las palabras cada 5 s.
- Ojo con la carga de GPU como medidor: arrastrar/masear carga la GPU, así que
  un gauge en vivo se llena por el propio gesto. Mostralo en el texto, no en el
  dibujo.
- Un `Canvas` en reposo que gira se actualiza a 33 ms, no al refresco del
  display: es una rotación en GPU, no una animación de contenido.

## Accesibilidad

- `Esc` cierra, `Espacio`/`Enter` alterna, flechas mueven la selección, y cada
  gesto del mouse tiene su tecla. El canvas no recibe foco: el foco va a un
  `Item` con `Keys.onPressed`.
- Con animaciones apagadas (`~/.local/state/omarchy/animations-enabled`), el
  morph tiene que durar 0: se aplica `cur = to` y se salta el canvas. Nada de
  "el canvas igual aparece porque es más simple".
- Hover sobre un anillo explica qué es cada marca; sin eso, un dibujo abstracto
  no comunica nada. El pie de la tarjeta dice la verdad del dato en una frase.

## Verificación (los tres son deterministas)

1. **Estático** — `scripts/verificar-morph.sh <carpeta>`:
   `Math.random()` en dibujo, `fillText`, `requestPaint` dentro de `onPaint`,
   `Behavior` sobre el tamaño del canvas, `FrameAnimation` sin compensación,
   repintado por `Timer` sin `Frames`, ausencia de reduced motion y
   `fillStyle` por punto. Sale 1 si hay errores.
2. **Presupuesto por frame** — `scripts/bench.py HARNESS.qml [12] [frames]`.
   El harness dibuja con `renderStrategy: Canvas.Immediate` (rasteriza en el
   hilo de GUI dentro de `onPaint`, así que el tiempo incluye el rasterizado),
   cronometra paint + `getImageData(0,0,1,1)` e imprime
   `RASTER mean=… p95=… max=…`. Falla si la media pasa el presupuesto.
3. **Formas** — `scripts/shots.py HARNESS.qml OUT_DIR nombre...` renderiza
   offscreen (`QT_QPA_PLATFORM=offscreen`) y guarda un PNG por forma con
   `grabToImage`. Falla si hay `ReferenceError`/`TypeError`/binding loop o si
   falta un PNG. Mirá los PNG: el estado intermedio (`medio`) es el que revela
   si el morph es hermoso o un revoltijo.

Harness de shots (mínimo que funciona, comprobado):

```qml
ShellRoot {
  id: root
  property var steps: [["circulo", 1], ["medio", 0.5], ["filas", 0]]
  property int step: 0
  FloatingWindow {
    implicitWidth: 800; implicitHeight: 480; color: "#101315"
    Rectangle { id: frame; anchors.fill: parent; color: "#101315"
      Canvas { id: cv; anchors.fill: parent; property real shape: root.steps[Math.min(root.step, 2)][1]
        onShapeChanged: requestPaint()
        onPaint: { /* … Puntos.drawBeads(c, marks, Puntos.mixProj(PL, PC, shape), 1) … */ }
      }
    }
  }
  // Hace falta un pedido de paint periódico: sin él, offscreen no renderiza
  // y grabToImage devuelve una imagen vacía.
  Timer { interval: 33; repeat: true; running: true; onTriggered: cv.requestPaint() }
  Timer { interval: 1600; repeat: true; running: true
    property bool grabNext: false
    onTriggered: {
      if (grabNext) {
        frame.grabToImage(function(r) { r.saveToFile(root.steps[root.step][0] + ".png") })
        root.step++; grabNext = false
        if (root.step >= root.steps.length) { stop(); quitTimer.start() }
        return
      }
      cv.requestPaint(); grabNext = true
    }
  }
  Timer { id: quitTimer; interval: 600; onTriggered: { console.log("SHOTS_OK"); Qt.quit() } }
}
```

`saveToFile` va con nombre relativo: `shots.py` corre `qs` con el cwd en
`OUT_DIR`. Un `saveToFile` con ruta absoluta inventada (o un placeholder sin
reemplazar) devuelve `false` y no guarda nada: verificá el `ok=` del callback
si dudás.

## Receta de build-in de apertura

1. `cur` arranca en la forma final y `builtAt = now()`.
2. Cada elemento multiplica su alfa por
   `ease(clamp((t - builtAt - i*45) / 420, 0, 1))`.
3. Un `Timer` de 1100 ms marca `building = false` y habilita el motor de capas.
4. El canvas se mantiene hasta que las capas de la tanda estén arriba.

Ese "se dibuja solo de a uno" es la mitad del encanto inicial: la otra mitad es
que el primer frame ya tiene datos (leé la máquina cuando carga el plugin, no
cuando abrís la ventana).

## Anti-patrones

- Interpolar `x/y/width` de N ítems para "simular" el morph: no hay
  continuidad, se cruzan y no hay forma intermedia coherente.
- Un canvas a pantalla completa siempre corriendo para algo que está quieto el
  99% del tiempo (batería, GPU, fans).
- `Canvas` cuyo `width`/`height` se animan: reasigna el backing image por frame.
- Redibujar todas las capas cada vez que llega telemetría.
- Canvas sin `Math.max(clock + ms, lastT)`: temblor de un frame para atrás.
- Escalonar también cuando el usuario arrastra: el dedo se siente con lag.
- `Math.random()` por frame o semilla con `Date.now()`: la identidad se pierde.
- Texto `fillText` en el canvas junto a `Text` de QML en el mismo lugar.
- Alphas encimados en los mismos puntos: se ven manchas más oscuras.
- Handover sin handshake (`onPainted`): parpadeo de un frame en cada cambio.
- Un `Acrylic`/blur de fondo con un canvas encima que se redibuja: el blur se
  recompone por frame y el costo se dispara.

## Checklist antes de decir "listo"

- [ ] Un solo modelo `(u, w)` y dos proyecciones; el peso es por elemento.
- [ ] Los marks se arman una vez por morph y se invalidan por clave, no por frame.
- [ ] Las posiciones por frame reusan arrays; no hay allocation por punto.
- [ ] El canvas de morph usa `Frames` (o la compensación `+ms` y `Math.max`).
- [ ] Handover: capas dibujadas una por frame, avisadas por generación, canvas
      se desvanece después del último aviso.
- [ ] En reposo no hay canvas corriendo; el giro va a 33 ms.
- [ ] `scripts/verificar-morph.sh` sin errores.
- [ ] `scripts/bench.py` dentro de 12 ms (en esta máquina, aim ≤ 8).
- [ ] `scripts/shots.py` sin warnings y el PNG `medio` mirado a ojo.
- [ ] Con animaciones apagadas, el cambio de forma es instantáneo y usable.
- [ ] Probado en el panel real, abierto por el usuario.
