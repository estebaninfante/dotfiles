---
name: speeedy-world
description: >
  Construccion y modificacion del MUNDO del juego de Speeedy. Multi-escena:
  exterior "VILLA LECTORA" (pueblo, cabaña/casa, plaza, huerto, lago) y
  biblioteca "TU MENTE" (sala de lectura, recepcion, observatorio, aula,
  hogar). Cargar cuando el usuario pida "modificar el mundo", "mejorar el
  mapa", "la biblioteca", "el pueblo", "el exterior", "mi casa", "la
  cabaña", "construir el mundo", "nueva zona", "agregar props", "muebles",
  "pixel art", "que se vea mejor el mundo", "mas detalle en el mundo",
  "integrar mas detalles", o cualquier cambio en world-model /
  world-renderer / world-content / game-world / game-page. Incluye el flujo
  deterministico para que cada iteracion sea mas facil y con mas detalle
  que la anterior.
---

# Speeedy World

El mundo es un plano tile-based (canvas 2D, tile 16px) dentro de la app
RSVP Speeedy (Lit + TS + Vite). Objetivo permanente: que **construir el
mundo sea cada vez mas facil** y que cada iteracion **integre mas detalle**
que la anterior. Este skill captura el flujo, las reglas de diseno pixel
art (estilo Stardew Valley) y las herramientas de verificacion.

## 0. Reglas duras (no negociables)

1. **Cero comentarios en el codigo** (plugin `no-comments` BLOQUEA el edit).
   El codigo se explica con nombres y tipos. El "por que" va aqui, en el
   skill, no en el codigo.
2. **Tipos fuertes y exhaustivos**: `TileKind` es una union; todo `Record`
   derivado (`TILE_STYLE`, `SOLID_BY_KIND`) debe cubrir TODOS los kinds.
   Un kind nuevo sin renderer debe fallar en compilacion, no en runtime.
   `drawTile` termina en `assertNeverTile(kind)`.
3. **Sin fallbacks silenciosos**: caracter de mapa desconocido = `throw` en
   `createWorld`. No inventar tiles.
4. **Tests verdes antes de cerrar**: `pnpm exec tsc --noEmit`, `pnpm lint`,
   `pnpm test`. La navegacion teclado/gamepad no debe romperse (Arriba/Abajo
   mover, Derecha/Enter entrar, Izquierda/Escape volver).
5. No commitear salvo pedido explicito.

## 1. Arquitectura (donde vive cada cosa)

| Archivo | Rol |
|---|---|
| `src/services/world-model.ts` | Modelo: `TileKind`, `GROUND_CHARS` (char→kind), `SOLID_BY_KIND`, `createWorld`, `tileAt`, `isSolidTile`, `canStand`, `movePlayer`, `nearestInteractable`, `cameraFor`, `worldSize`, `tileCenter`. |
| `src/data/world-content.ts` | Contenido multi-escena: tipos `SceneId`/`ScenePortal`/`SceneDef`/`WorldInteractable`, `OUTDOOR_GROUND` (36x22), `LIBRARY_GROUND` (34x20), `OUTDOOR_INTERACTABLES`, `LIBRARY_INTERACTABLES`, `SCENES: Record<SceneId,SceneDef>`, `START_SCENE`. |
| `src/data/world-content.test.ts` | Tests de integridad de escenas (anchos, spawn caminable, anclas alcanzables, portales validos, `enterActivity` resuelve). |
| `src/services/world-renderer.ts` | Render puro: `TILE_STYLE`, `CONTACT_SHADOW`, `drawTile`, `drawWorldTiles`, `drawInteractable`, `drawPlayer`, `drawWorldOverview`, `overviewZoom`, `hash2`. |
| `src/components/game/game-world.ts` | Custom element `game-world` scene-aware (`scene`, `spawn` props): input teclado/gamepad, hitbox, camara/zoom cover, `?world=map` (overview), dispatch `world-interact`. |
| `src/components/game-page.ts` | Host de pantallas y **dueno de la escena**: portal handling (`enterScene`), `enterActivity`, dialogos de actividad, `renderReadingPanel`, `renderActivity`. |
| `scripts/world-shot.mjs` | Harness Playwright de captura (screenshot overview + jugador). |

## 1b. Sistema de escenas (multi-mapa)

Hay **dos escenas** (`SceneId = "outdoor" | "library"`) definidas en `SCENES`:

- `outdoor` ("VILLA LECTORA", 36x22): arranque del juego (`START_SCENE`). Cabaña
  del jugador (portal adentro), casa vecina, plaza con fuente, jardin, huerto,
  lago con puente, borde de arboles.
- `library` ("TU MENTE", 34x20): interior. Fila 0 y fila 19 = muro; puerta `DD`
  en x16-17; fila 1 = muro norte con decoracion; piso interior filas 2-18.

Reglas del sistema:

- Un `WorldInteractable` tiene `activity?` **o** `portal?: {scene,tileX,tileY}`
  (uno de los dos). Portal = viaje entre escenas (`casa` → library; `salida` →
  outdoor).
- `SceneDef.enterActivity?: string` = interactable que se **abre automaticamente**
  al entrar a la escena. `library` tiene `enterActivity: "continuar"` para que,
  al entrar, lo mas importante (lectura actual + libros) aparezca de una.
- `game-page` es el dueno de `scene`/`spawn`; `enterScene(portal)` cambia escena,
  reubica el spawn en `tileCenter(portal.tileX,portal.tileY)`, resetea
  actividad/result/level y dispara `enterActivity`. El `<game-world>` se monta
  con `keyed(this.scene, ...)` para remontar limpio al cambiar escena.
- `?scene=library` arranca en una escena (util para screenshots); `?world=map`
  usa la escena activa.

## 2. Como agregar un `TileKind` (7 pasos, en orden)

1. `world-model.ts` — agregar el literal a la union `TileKind`.
2. `world-model.ts` — mapear un char unico en `GROUND_CHARS`.
3. `world-model.ts` — declarar `true`/`false` en `SOLID_BY_KIND`
   (exhaustivo; `tsc` falla si falta).
4. `world-renderer.ts` — agregar paleta `{base, alt, detail}` en `TILE_STYLE`.
5. `world-renderer.ts` — agregar rama en `drawTile` (antes del `assertNever`
   final). Si proyecta sombra al piso, sumar el kind a `CONTACT_SHADOW`.
6. `world-content.ts` — usar el char en `WORLD_GROUND` (y alinear el
   interactable, ver seccion 3).
7. Verificar: `pnpm exec tsc --noEmit && pnpm lint && pnpm test`.

Runs multi-tile: `drawTile` ya recibe `map` y calcula `runUp/runDown/runLeft/
runRight` (vecino del MISMO kind). Usarlo para que estanterias verticales y
mesas horizontales se lean como un mueble continuo (sin costuras de modulo).
Regla: **todo prop compuesto debe usar esto** — evita el "apilado modular".

## 3. Layout y alineacion de interactables

`WORLD_INTERACTABLES` define `{id, tileX, tileY, emoji, label, accent,
activity}`. El `tileX/tileY` DEBE caer sobre el prop que lo representa y
tener un tile caminable adyacente (a <= 1.75 tiles, radio de
`nearestInteractable`). Coords actuales:

Biblioteca (`LIBRARY_INTERACTABLES`):

| id | tile | tipo | prop/rol |
|---|---|---|---|
| continuar | 17,17 | activity | umbral de entrada; abre lectura actual + libros (`enterActivity`) |
| sala-lectura | 17,9 | activity | mesa `t` del centro |
| biblioteca | 1,6 | activity | estante `S` del muro izquierdo |
| observatorio | 31,3 | activity | globo `g` |
| recepcion | 15,16 | activity | registro `k` del mostrador |
| aula | 29,12 | activity | podio `z` |
| salida | 16,19 | portal→outdoor (6,5) | puerta `DD` |

Exterior (`OUTDOOR_INTERACTABLES`):

| id | tile | tipo | prop/rol |
|---|---|---|---|
| casa | 6,4 | portal→library (16,18) | puerta `D` de la cabaña |
| letrero | 10,6 | activity | cartel `!` |
| pueblo | 18,10 | activity | fuente `Y` de la plaza |
| jardin | 17,4 | activity | banco `j` del rincon |
| huerto | 28,17 | activity | cultivo `V` |
| lago | 8,17 | activity | agua `~` |

**Validacion automatica**: `src/data/world-content.test.ts` verifica que el
spawn y cada ancla caigan en un tile no solido o tengan vecino caminable, y que
cada portal apunte a escena conocida y tile no solido. Correr `pnpm test` tras
mover props.

## 4. Editar el mapa con el script de pintado (recomendado)

No editar las 20 filas a mano: usar el patron de
`/tmp/opencode/map-build.mjs` (Paint API + validacion). Borrador:

```js
const W = 34, H = 20;
const grid = Array.from({length:H},()=>Array.from({length:W},()=>"#"));
const rect=(x0,y0,x1,y1,ch)=>{for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++)grid[y][x]=ch;};
const put=(x,y,ch)=>{grid[y][x]=ch;};
rect(1,2,32,18," ");
rect(2,13,6,14,"R");
const known=new Set(".,=~sfT rStpcw#DPRhblFao gzkLOMCAnKUdiqxEZBHVjIu!".split(""));
const rows=grid.map(r=>r.join(""));
for(const [i,r] of rows.entries()){
  if(r.length!==W) throw new Error(`row ${i} len ${r.length}`);
  for(const ch of r) if(!known.has(ch)) throw new Error(`unknown ${ch}`);
}
console.log(rows.map(r=>JSON.stringify(r)).join(",\n"));
```

Luego pegar las filas en `OUTDOOR_GROUND` (W=36,H=22) o `LIBRARY_GROUND`
(W=34,H=20). Ventaja: ancho garantizado y chars validados antes de tocar el
repo. Un char no listado en `known` debe existir en `GROUND_CHARS`, si no
`createWorld` lanza. Generador real del exterior: `/tmp/opencode/outdoor-build.mjs`.

## 5. Capturar screenshots (evaluacion visual)

`scripts/world-shot.mjs` usa Playwright chromium y captura el custom element
`game-world`:

```bash
# dev server (los puertos 5173/5174 suelen estar ocupados; usar el que salga)
pnpm dev
WORLD_URL="http://localhost:5175/?world=map#/game" node scripts/world-shot.mjs /tmp/opencode/world-map.png
WORLD_URL="http://localhost:5175/#/game"           node scripts/world-shot.mjs /tmp/opencode/world-play.png
```

Claves del harness (ya implementadas):

- Seed `localStorage["speeedy:life:v1"] = {created:true, areas:{...}}` con suma
  **27** (7 areas * 1 base + 20 pool). Suma 20 NO completa la asignacion y
  desvia a creacion de personaje. Si cambian las areas base del onboarding,
  recalcular.
- Salta el onboarding con `[data-umami-event="onboarding-skip"]`, espera
  `game-page`, click en `.gp-title-menu button`, espera `game-world canvas`.
- **Playwright borra `test-results/` en cada run**: guardar PNGs en
  `/tmp/opencode`, nunca en `test-results`.
- `?world=map` activa el overview que encaja el mapa completo centrado
  (`drawWorldOverview` + `overviewZoom`); sin el, es la vista jugador con zoom
  cover (`zoomFor = max(2, ceil(max(w/worldW, h/worldH)))`).

## 6. Flujo de evaluacion (rating loop)

Para pedidos de "mejorar el mundo", correr iteraciones con un evaluador
externo que puntue **codigo + visual** como disenador de interiores pixel art
(estilo Stardew Valley):

1. Capturar overview + jugador (seccion 5).
2. `task` (subagent_type `general`) con este prompt: rol = disenador de
   interiores de videojuegos pixel art; leer las 2 imagenes + `world-renderer.ts`,
   `world-content.ts`, `world-model.ts`; exigir formato: `NOTA FINAL X.X/10`,
   desglose por 6 criterios, Top 5 cambios por impacto con archivo:linea o
   coordenada de tile, y veredicto `APROBADO` si `>=9` sino `RECHAZADO`.
3. Iterar: aplicar los cambios de mayor impacto y repetir. **Parar cuando
   NOTA >= 9.0 o al llegar a 3 rondas, lo que ocurra primero.**
4. Al cerrar, actualizar este skill con lo aprendido (seccion 7).

Criterios de la rubrica (0-10, 6): zonificacion, composicion/focalidad,
variedad/densidad, circulacion, color/legibilidad pixel, codigo/arquitectura.
Un evaluador fresco cada ronda: la nota es ruidosa, pero los comentarios son
accionables — implementar los de mayor impacto, no perseguir el numero.

## 7. Principios de diseno aprendidos (Stardew-like)

Zonificacion:
- Las zonas se leen por **piso, no por props sueltos**. Diferenciar suelo
  (`floor` / `floor2` / `tilefloor` / `rug` / `rug2`). Evitar un unico piso
  marron: aplana todo.
- Reservar acentos de piso por zona y **no repetir el mismo piso en zonas
  distintas** (observatorio y aula NO deben compartir `tilefloor`; usar un
  piso oscuro/pizarra para el observatorio).

Composicion:
- **Romper la simetria** (muro norte, bloques de muebles). El ojo lee simetria
  perfecta como "gimnasio/folleto", no como interior vivido.
- Cada zona necesita **focal propio**: borde ancla a muro, pieza grande,
  o run multi-tile. Una zona con props 1x1 flotando en vacio se lee como
  paraiso vacio.
- **Densidad pareja**: cubrir uniformemente; los cuartos vacios (ej. filas
  centrales sin nada) se notan mas que un prop feo.

Legibilidad pixel:
- **Contraste**: props marrones sobre piso marron desaparecen. Los props
  claros (`openbook`/`candle`) sobre `tilefloor` claro se lavan. Subir el
  contraste con outline o piso mas oscuro.
- **Sombras de contacto** en todo mueble que se apoya (helper `CONTACT_SHADOW`,
  elipse `rgba(0,0,0,0.17)`); sin ellas todo "flota".
- **Multi-tile continuo** con `runUp/runDown/runLeft/runRight`; nunca apilar
  modulos identicos.
- Micro-historias venden el mundo: gato durmiendo junto al hogar, globo +
  candela en observatorio, podio + pupitres en aula.

## 8. Estado actual y deuda abierta

Interior: tres rondas de eval (6.4 -> 6.0 -> 7.7). Mejoras aplicadas: pisos por
zona, muro norte asimetrico, vacio central poblado, sombras de contacto,
`SOLID_BY_KIND` exhaustivo, `createWorld` lanza en char desconocido, runs
multi-tile. Exterior entregado junto con el sistema de escenas/portales y el
`enterActivity` de biblioteca.

Pendientes de mayor impacto (para la proxima iteracion de mundo):
1. **Observatorio del interior vacio** (cols 24-32, filas 2-6): llenar con
   telescopio multi-tile, 2-3 puestos, piso pizarra oscuro que lo separe del aula.
2. **Exterior densificable**: orilla del lago, mercadillo con toldos, huerto con
   cerca decorativa, mas micro-historias (perro, carreta, pozo).
3. **Fallback residual de padding** en `createWorld` (`char === undefined →
   "grass"`): decidir si lanzar o documentar (hoy pasa el test de padding).
4. Codigo muerto: `BuildingDef`/param `buildings` (`createWorld(..., [])`).
5. `CONTACT_SHADOW` es un `Set` manual: derivarlo de metadata por kind para
   que no se desincronice al agregar props.
6. Emojis/labels de interactables se dibujan en espacio de mundo y escalan con
   el zoom de juego (se ven grandes en la vista cercana): moverlos a HUD si
   molesta.
