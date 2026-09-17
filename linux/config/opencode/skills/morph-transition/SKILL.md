---
name: morph-transition
description: Use when animating a persistent UI element that changes shape/size/position between two states — "morph transition", "shared element", "transformar orbe en barra", "cápsula", "transición entre input y orbe", morph de un elemento entre rutas o modos, entrada/salida de capas animadas, or when a WebGL/canvas element (react-three-fiber, orbe) participates in a layout transition. Also use when a morph looks wrong: se solapa, parpadea, salta, queda negro, o "no se siente morph".
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
3. **Los centros coinciden.** Reserva el hueco del destino en el estado grande
   (`margin-bottom`) para que el centro de origen caiga sobre el del destino: la
   silueta se desploma sobre su reflejo, no salta a otro sitio.
4. **El contenido compartido viaja y encoge**, no se desvanece en el centro:
   `translateX(calc(50% - Npx))` (N medido contra el borde del contenedor) y
   `scale`. El color no se pierde: se *drena* interpolando hacia la paleta
   destino (el destino conserva el color en su propio acento).
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
  CSS con la paleta del elemento. Sin esto queda un agujero negro.
- `prefers-reduced-motion` → resolver capacidades con `useSyncExternalStore`
  (servidor `"pending"`, cliente `"webgl" | "fallback"`), nunca escribiendo
  estado en un `useEffect`.

## Prohibiciones

- Re-montar o truecar el elemento compartido.
- Animar `width`/`height` del contenedor de un canvas WebGL.
- `filter: grayscale/blur` en la cadena del canvas.
- `overflow-hidden` en el escenario (recorta el elemento y su halo); sí en la
  silueta cuando hay que recortar el barrido.
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
4. Limpiar procesos por PID (`ss -ltnp`). `pkill -f "<patrón>"` se mata a sí
   mismo si el patrón aparece en el comando: nunca usarlo.
