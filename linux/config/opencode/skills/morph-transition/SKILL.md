---
name: morph-transition
description: Use when animating a persistent UI element that changes shape/size/position between two states — "morph transition", "shared element", "transformar orbe en barra", "cápsula", "transición entre input y orbe", morph de un elemento entre rutas o modos, entrada/salida de capas animadas, or when a WebGL/canvas element (react-three-fiber, orbe) participates in a layout transition. Also use when a morph looks wrong: se solapa, parpadea, salta, queda negro, o "no se siente morph". Also use when a morph/transition is slow or janky on mobile — "va a 3 fps", "se traba en iPhone", "lag", "jank", "bajo rendimiento", animation performance on iOS/WebKit, or optimizing a transition that animates layout with backdrop-filter/filter/mask/will-change.
---

# Morph transition (elementos persistentes)

Receta destilada del cockpit de agentes (orbe ↔ barra de entrada). Versión larga
y checklist: `docs/morph-transition.md` del repo si existe; esta skill es la
guía operativa.

## Regla madre

**Una sola materia.** Un elemento que se transforma, no dos que se turnan.
Si el elemento compartido se desmonta, se apaga o se trueca por otro (icono,
placeholder), ya no es morph: es un fundido cruzado.

## Receta

1. **Vive en el layout/shell, no en la página.** Al navegar dentro del route
   group no se desmonta: solo cambian sus props.
2. **Silueta = geometría animada.** Círculo → píldora animando `width`,
   `height`, `border-radius` (misma curva). El contenedor/escenario también
   anima su alto (`transition-[height]`).
   - **TODA propiedad geométrica que cambie con el modo debe estar en la misma
     transición** (`height`, `min-height`, `margin`, `padding`). Una que falte no
     se interpola: salta a su valor final en el primer frame y el morph arranca
     ya desplazado (el input "subía de golpe" antes de transformarse por un
     `min-height` fuera del `transition`).
   - **Nunca `min()`/`max()`/`clamp()` dentro de una propiedad que se anima**: no
     está garantizado que un motor no-Chromium interpole la comparación. El techo
     se resuelve con una **custom property** plana por breakpoint (`--stage-voice-h`
     en `:root` + media query) y se anima la var.
   - **El `padding` de un nodo en el flujo mueve la silueta**: transiciónalo o
     elimínalo.
3. **Los centros coinciden.** Reserva el hueco del destino en el estado grande
   (`margin-bottom`) para que el centro de origen caiga sobre el del destino: la
   silueta se desploma sobre su reflejo, no salta a otro sitio.
4. **El contenido compartido viaja y encoge**, no se desvanece en el centro:
   `translateX(calc(50% - Npx))` y `scale`. El color no se pierde: se *drena*
   interpolando hacia la paleta destino (el destino conserva el color en su
   propio acento).
   - **CRÍTICO (iOS/WebKit):** ese `%` se resuelve contra **su propia caja**, así
     que la capa que viaja debe tener **tamaño constante** (el ancho destino),
     centrada con `top-1/2 left-1/2` + `translate(-50%,-50%)`. Si la capa es
     `inset-0` de la silueta que anima `width`, WebKit **no recalcula el `%` por
     frame** (Chromium sí): el elemento se queda en el centro y salta al terminar,
     y el contenido se recomprime detrás. Es el bug clásico "en Android se ve
     bien, en iPhone no".
5. **Timeline separada.** La capa saliente se apaga y se recoge hacia el centro
   ANTES de que la entrante aparezca (la entrante lleva delay). Nunca en el
   mismo instante. Ej.: saliente 0-180ms, entrante 330-610ms, morph 0-620ms.
6. **Capas por responsabilidad**, cada una con su `pointerEvents`:
   barrido de luz recortado a la silueta → elemento compartido (nunca se apaga)
   → capa del modo saliente → capa del modo entrante.
7. **Controles en cascada**: `opacity` + `translateY/scale` con delay
   incremental (`100 + i * 55`ms). Una constante para entrada, otra (más corta)
   para salida.
8. **Detalles materiales**: barrido de luz una vez por cambio (remontado con
   `key`), glow que se abre desde el centro (`scaleX(0.25)` → 1), leyenda que
   se re-monta con `key` + keyframe de entrada (no cambio seco), apagar el bloom
   cuando el elemento es chico.
9. **Un cambio de fondo por color es un cruce, no un reemplazo.** Si el layer
   viejo se desmonta y el nuevo entra desde `opacity: 0`, durante el fundido se ve
   el color plano del contenedor: flash seco (bug "el fondo cambia abruptamente al
   navegar"). Se renderizan los DOS a la vez —saliente con `out`, entrante con
   `in` (keyframes complementarios, misma curva)— y el saliente se desmonta al
   terminar (estado `{ current, prev }`, ajustado en el render, no en un efecto).
10. **Lo persistente que cambia con la ruta entra con fade.** Un rótulo del shell
    (nombre del agente) no se re-monta solo: si no, aparece de golpe mientras el
    resto de la vista se desvanece. `key={ruta}` + un keyframe corto de opacidad
    con un desplazamiento mínimo (costo de compositor).

## Constantes

Una sola duración y curva, compartida por TODO lo que participa:
`620ms cubic-bezier(0.32,0.72,0,1)` (`MORPH` en clases, `MORPH_EASE` en inline).
Si cambia, cambiar en todos los sitios.

## WebGL / canvas (si el elemento lo tiene)

- Renderizar SIEMPRE a tamaño fijo en px (`BASE`) y morphar con
  `transform: scale(size / BASE)`. Nunca animar su caja: el buffer del canvas se
  reajusta (con debounce) y se ve a saltos. Escalar es compositor.
- `react-use-measure` mide con `getBoundingClientRect()` (tamaño YA escalado):
  usar `resize={{ offsetSize: true }}`. Sin esto el canvas se pinta diminuto
  arriba a la izquierda y parece "negro"/vacío.
- **`filter` sobre un ancestro del canvas puede blanquearlo** según la GPU
  (en software no se reproduce). Nunca `grayscale`/`blur` para cambiar el look:
  usar la paleta del shader.
- **Nunca una capa CSS debajo del shader** (con `mix-blend-screen`): lava el
  color y cambia la identidad del elemento; y para conservar contraste la capa
  de abajo tendría que ser negra (inútil como respaldo). El respaldo CSS solo va
  como **reemplazo**.
- **Watchdog**: el contexto puede no crearse o morir (driver, límite de
  contextos, HMR). Buscar el `<canvas>`, escuchar `webglcontextcreationerror` /
  `webglcontextlost` (margen ~2s a la restauración de three) /
  `webglcontextrestored`, y tras ~1200/3500ms sin contexto sano caer a la esfera
  CSS con la paleta del elemento. Sin esto queda un agujero negro. Dos reglas
  que costaron caro: **una pérdida de contexto no es una lápida** (al
  `webglcontextrestored` se vuelve al shader; dejar el flag en `true` para
  siempre deja el respaldo definitivo) y **el canvas de sondeo se suelta**
  (`WEBGL_lose_context.loseContext()`), porque iOS topa los contextos vivos por
  página y tras varios reloads el sondeo devuelve `null`.
- **"Hay contexto" no es "hay píxeles"**: inspeccionar el `<canvas>` desde fuera
  (contexto sano + 2 rAF) para decidir que el orbe está listo funciona en
  Chromium y **no** en iOS, donde el respaldo se queda encima para siempre. La
  señal fiable la da el shader (`onReady` en el primer `useFrame` con material),
  con un tope de tiempo como red de seguridad.
- `prefers-reduced-motion` → resolver capacidades con `useSyncExternalStore`
  (servidor `"pending"`, cliente `"webgl" | "fallback"`), nunca escribiendo
  estado en un `useEffect`. Pero esa preferencia **no** decide el soporte de
  WebGL: el elemento con canvas es contenido, no adorno (y si no, queda su
  respaldo CSS como versión definitiva para todo usuario con "reducir
  movimiento").

## Rendimiento en móvil (iOS/WebKit y gama baja)

Un morph de 620 ms que anima layout y lleva canvas puede caer a **3 fps en
iPhone** aunque en desktop/Android vaya fino. Causas reales ya encontradas:

- **`backdrop-filter` sobre el canvas WebGL**: iOS relee el backdrop compuesto
  cada frame; si el nodo además se redimensiona con el morph, mata la
  transición. Controles con `bg-card` sólido + `box-shadow`, sin vidrio. Si se
  quiere glass, que sea clase condicional y **nunca** sobre/anidado al canvas.
- **`will-change` en un nodo que se redimensiona**: promueve una capa del
  tamaño equivocado y la re-rasteriza por frame. Como regla: no declararlo; el
  morph ya compone. Si hace falta, solo en el nodo que de verdad transforma.
- **No animar el `dpr` del canvas** (ni 0.5↔1) durante el morph: cada cambio
  reajusta el buffer y se ve a saltos. Si se baja resolución, fijo, decidido
  antes de pintar. Ojo con los "hacks" que suben/bajan `dpr` con un timeout
  justo tras el morph: son la causa, no el arreglo.
- **`mask-image` y `filter: blur()` grandes** rasterizan áreas enormes y a
  menudo offscreen. El `blur` del glow de fondo y el `mask` de degradado del
  scroller son **adorno**: apágalos en táctil.
- **`overflow-hidden` + `rounded-full` sobre el canvas** fuerza una máscara
  redondeada recomputada por frame. Si el shader ya dibuja un disco, no clips
  el marco.
- **No reflowear el contenedor de una capa**: el ancho de la silueta es una
  constante compartida; los hijos van en cajas de tamaño fijo (ver regla 4).
  Un contenedor que muta re-layouta y recomprime a todos sus descendientes.
- **No tocar la sesión de audio (getUserMedia / AudioContext) dentro del morph**:
  en iOS activar el micrófono **y también soltarlo** (`track.stop()` +
  `AudioContext.close()`) bloquea el hilo principal; la silueta (que anima
  layout) se congela mientras el orbe (transform, compositor) termina y se ve la
  píldora ancha detrás del orbe grande, con el cambio "tardando". Aplazar tanto
  el arranque como la suelta a después del morph (~660 ms). El estado visible y
  el loop de nivel se cortan en el acto; lo que espera es el hardware.
- **Mutear es un flag, no un arranque/parada.** `track.enabled = false` silencia
  sin tocar la sesión de audio: barato e instantáneo. Hacerlo parando/arrancando
  el micrófono bloquea el hilo principal en iOS y, si cae dentro de una
  animación, se traba la escena entera (no solo el botón). El nivel se lee 0
  mientras está en silencio.
- **El control se pinta con la intención, no con el hardware.** Si el estado
  visible espera a `active`, salta unos cientos de ms después (cuando arranca la
  sesión). Y un `start()` que llega tarde (el usuario ya salió del modo) debe
  apagarse al llegar: contador de generación en `release()`.
- **Un glow de fondo es una capa más del fondo, nunca un nodo aparte.** Un div
  propio, de caja chica, `rounded-full` y degradado dimensionado en `%` es un
  bug esperando: en WebKit el tamaño en `%` de la elipse puede caer a
  farthest-corner (el color no llega a transparente en el borde de la caja y
  asoma el rectángulo, sobre todo sin blur) y además es una capa compuesta más
  que iOS rasteriza como placa gris durante el cruce de opacidades. Va como
  entrada del `background` de la capa de fondo a **pantalla completa**: aunque
  el motor ignore el tamaño, el borde duro cae fuera del viewport. Sin `filter`.
- **El respaldo de un canvas se revela, no se trueca.** No desmontar la esfera
  CSS al montar el canvas: mientras el canvas no pintó su primer frame se ve el
  marco vacío y el elemento aparece de golpe ("color pleno → negro → real"). El
  respaldo se queda ENCIMA hasta que el watchdog ve el contexto sano + 2 frames,
  y se apaga con un fundido; después se desmonta. Su animación escribe `opacity`,
  y una animación gana sobre cualquier declaración normal (y sobre las utilidades
  de Tailwind, que van en capas): hay que apagarla para que el fundido mande.
- **Un rótulo persistente del shell que cambia con la ruta entra con fade**
  (`key={pathname}` + opacidad y un desplazamiento corto). Es persistente, así
  que no se re-monta solo: si no, aparece de golpe mientras el resto se va.
- **El watchdog de un canvas no debe rendirse por lentitud.** Esperar un
  deadline holgado antes de caer al respaldo CSS; un canvas que aún no aparece
  es carga, no muerte.

**Regla de gama baja**: en táctil se apaga el adorno, no el morph:

```css
@media (pointer: coarse), (max-width: 720px) {
  .composer-glow { animation: none; }
  .orb-fallback { animation: none; }   /* respaldo del canvas: quieto */
  .capsule-sheen, .sheen-clip { display: none; }
  .stream-mask { mask-image: none; -webkit-mask-image: none; }
}
```

Detección de dispositivo: `matchMedia("(pointer: coarse)").matches ||
innerWidth < 720` (false en SSR). No confundir con el fallback de WebGL, que es
otra cosa (`useSyncExternalStore`).

## Qué puede animar (presupuesto de cada frame)

- **Compositor (barato):** `transform`, `opacity`. Todo lo que deba seguir
  fluido durante el morph va por acá.
- **Main thread (caro, repintado por frame):** `width`, `height`, `top/left`,
  `margin`, `padding`, `border-radius`, `box-shadow`, `filter`, `mask-image`,
  `background`. En un morph la **silueta** necesita geometría (es la excepción
  deliberada), pero ningún otro nodo debería animar layout: los hijos van en
  cajas de tamaño constante que solo `transform`an.

## Síntomas → causa

| Síntoma | Causa | Fix |
| --- | --- | --- |
| 3 fps solo en iPhone; en Android/PC fino | `backdrop-filter`, `will-change` en un nodo que cambia de tamaño, `blur()` grande, `mask-image`, `overflow-hidden`+`rounded-full` sobre el canvas | apagar el adorno en táctil; controles `bg-card` sólido; sin `will-change` |
| El elemento se queda en el centro y **salta al terminar**; en Android bien | `%` de `transform` contra la caja que anima `width` (WebKit no lo recalcula por frame) | caja de tamaño constante centrada con `top-1/2 left-1/2` + `translate(-50%,-50%)` |
| Píldora ancha **congelada** detrás del elemento ya grande, en cualquier sentido | sesión de audio tocada dentro del morph (arrancar o soltar) | aplazarla a que el morph termine |
| Al darle a mute/unmute **se traba todo** | mute = parar/arrancar el micrófono (bloquea el hilo en iOS) | mutear con `track.enabled = false`; visible por intención |
| El botón de micrófono **salta** al entrar en modo voz | el estado visible esperaba a `active` (la sesión tarda ~660 ms) | `micEnabled` (intención) para pintar; hardware después |
| **Rectángulo** de la caja del glow visible en móvil (y placa gris encima del contenido al navegar) | glow como nodo aparte: el `%` del degradado cae a farthest-corner y es una capa compuesta que iOS rasteriza mal | glow como capa del fondo a pantalla completa (borde duro fuera del viewport) |
| El elemento **color pleno → negro → real** al recargar | el respaldo CSS se desmonta al montar el canvas, que tarda en pintar | respaldo ENCIMA hasta la señal del shader (`onReady`) y fundido de salida (`animation: none` para que el fundido mande) |
| Un rótulo del shell **aparece de golpe** al navegar | es persistente y cambia con la ruta | `key={pathname}` + entrada suave (opacidad + desplazamiento corto) |
| El **respaldo CSS queda como elemento definitivo** (solo en iPhone) | "hay contexto" ≠ "hay píxeles": la inspección externa del canvas no llega en WebKit; y/o el flag de muerte era irreversible tras una pérdida de contexto | `onReady` desde el primer `useFrame` con material + tope de tiempo; `webglcontextrestored` devuelve el shader |
| El respaldo vuelve **tras varios reloads** y ya no se va | el sondeo de WebGL deja su contexto vivo y iOS topa el límite por página | soltar el contexto del sondeo (`WEBGL_lose_context.loseContext()`) |
| El elemento con canvas **nunca anima** en un equipo con "reducir movimiento" | `prefers-reduced-motion` usado para elegir el soporte WebGL | esa preferencia apaga adornos, no el contenido: la capacidad la decide solo WebGL |
| Aparece la **esfera CSS de respaldo** "porque sí" | watchdog que se rinde por lentitud (el canvas aún no montó) | deadline holgado, fallar solo por error real de contexto, `console.warn` del motivo |
| El elemento **sube de golpe** antes de transformarse, y recién ahí anima | una propiedad del flujo cambió sin estar en el `transition` (`min-height`) | transicionar TODA propiedad geométrica que cambie con el modo, o eliminarla |
| El **fondo cambia de golpe** al navegar (brillo → plano → brillo) | el layer viejo se desmonta y el nuevo entra desde `opacity: 0` | cruce de dos capas (saliente `out` + entrante `in`); desmontar la saliente al final |
| Canvas diminuto arriba-izquierda, o "negro"/vacío | `react-use-measure` mide con `getBoundingClientRect()` (ya escalado) | `resize={{ offsetSize: true }}` |
| El canvas se ve **a saltos** | se anima su caja o su `dpr` | tamaño fijo `BASE` + `scale()`; `dpr` decidido antes de pintar |
| El elemento queda **negro/blanco** según la GPU | `filter` sobre un ancestro del canvas | paleta del shader; nunca `filter` en la cadena |

## Diagnóstico de jank (método)

1. **Traza con CPU throttle** (CDP `Emulation.setCPUThrottlingRate`, ~6x) + un
   contador de frames por rAF. Un morph que anima layout se delata con
   `UpdateLayoutTree` / `Layout` / `Layerize` / `Commit` repetidos (y
   `LayoutDuration`/`RecalcStyleDuration` altos en `Performance.getMetrics`):
   ahí está el costo, no en el shader.
2. **Atribuir culpable por A/B**: inyectar un stylesheet que desactive **un**
   sospechoso por corrida (`backdrop-filter`, `filter`, `box-shadow`,
   animaciones, `will-change`, y por último la transición entera) y comparar
   frames. En este repo quitar cualquiera de esos casi duplicó los frames.
3. **Techo**: `transition: none` da el máximo de frames. Si con TODOS los
   adornos apagados el morph sigue lento, el costo es el repintado de layout
   (geometría/hijos que mutan), no un filtro.
4. **Límite**: en headless con swiftshader el raster es en CPU y el conteo es
   ruidoso (la misma config da 2, 14 y 16 frames). Da dirección y geometría, no
   fluidez. La fluidez se valida en dispositivo.

## Prohibiciones

- Re-montar o truecar el elemento compartido.
- Animar `width`/`height` del contenedor de un canvas WebGL.
- `filter: grayscale/blur` en la cadena del canvas.
- `backdrop-filter` (glass) sobre/anidado al canvas o en un nodo que se
  redimensiona con el morph.
- `will-change` en un nodo cuyo tamaño cambia durante el morph.
- Animar el `dpr` del canvas, o cambiar su resolución en/tras el morph.
- Resolver un `%` de `transform` (`calc(50% - Npx)`) contra una caja que anima
  `width`/`height`: usa una capa de tamaño constante centrada.
- Tocar la sesión de audio (`getUserMedia`/`AudioContext`, arrancarla **o
  soltarla**) en el tick en que empieza el morph: aplázalo a que termine (en iOS
  bloquea el hilo principal y congela la parte que anima layout).
- Mutear/desmutear parando/arrancando el micrófono (usa `track.enabled`).
- Pintar un control de hardware con el estado del hardware (usa la intención:
  el hardware llega tarde y el control salta).
- `overflow-hidden` en el escenario (recorta el elemento y su halo); sí en la
  silueta cuando hay que recortar el barrido.
- Dejar una propiedad geométrica que cambia con el modo fuera del `transition`
  (salta en un frame), o meter `min()`/`max()`/`clamp()` en una propiedad que se
  anima (usar var plana + media query).
- Desmontar el layer de fondo saliente al instante y montar el entrante: usa el
  cruce de dos capas.
- Sacar el glow de fondo a un nodo propio (caja chica + `rounded-full` +
  degradado en `%`): va en el `background` del fondo a pantalla completa.
- Desmontar el respaldo CSS de un canvas antes de que el canvas pinte (deja el
  marco vacío y un "pop"); y dejarle la animación viva durante el fundido de
  salida (la animación escribe `opacity` y gana sobre el fundido).
- Decidir que el canvas "ya está listo" inspeccionándolo desde fuera (contexto
  sano + 2 rAF): en WebKit eso no llega y el respaldo tapa el elemento para
  siempre. Que lo avise el propio shader.
- Dejar el flag de "shader muerto" en `true` para siempre: una pérdida de
  contexto transitoria nunca se recupera; al `webglcontextrestored` hay que
  volver.
- Dejar vivo el contexto WebGL del sondeo de capacidades (iOS topa el límite por
  página y el sondeo empieza a devolver `null`).
- Usar `prefers-reduced-motion` para decidir el soporte de WebGL (el elemento con
  canvas es contenido, no adorno: quedaría deshabilitado para siempre).
- Cruzar la capa que sale con la que entra.
- `setState` dentro de `useEffect` para reaccionar al modo
  (`react-hooks/set-state-in-effect` lo rechaza): ajustar el estado en el render
  (`if (menuMode !== mode) { setMenuMode(mode); if (mode !== "voice") setMenuOpen(false); }`).
- Dejar un menú/estado efímero abierto al cambiar de modo.
- `main` con `min-h-dvh`: usar `h-dvh` + `overflow-hidden` y scrollers internos
  `min-h-0 flex-1 overflow-y-auto overscroll-contain`.

## Verificación

1. `pnpm exec tsc --noEmit`, `pnpm lint`, `pnpm build`.
2. Servir el build y screenshotear con Chromium headless **en las dos rutas de
   GPU**: con `--use-angle=swiftshader --enable-unsafe-swiftshader` y sin ellas.
3. Fotogramas a ~110/300/600ms en ambos sentidos, en dos anchos (1000×820 y
   430×900): la capa saliente ya no está cuando entra la otra, el elemento viaja,
   el destino queda limpio.
4. **El rendimiento NO se juzga en headless.** Con swiftshader el raster es en
   CPU y el conteo de frames por rAF es ruidoso (la misma config da 2, 14 y 16
   frames en corridas distintas). Sirve para detectar el bug de geometría, no la
   fluidez. La fluidez real se valida **en dispositivo**, idealmente iPhone (el
   motor que rompe distinto es WebKit, no Chromium).
5. Limpiar procesos por PID (`ss -ltnp`). `pkill -f "<patrón>"` se mata a sí
   mismo si el patrón aparece en el comando: nunca usarlo.
