# Decisiones

Registro de decisiones de arquitectura del repo: qué se eligió, por qué y qué
se descartó. Las entradas no se reescriben; se agregan.

## 2026-10-19 — `liberar`: cerrar lo que no arrancó con el sistema

**Contexto.** Hacía falta una palabra en la terminal para soltar memoria y
procesos que quedaron dando vueltas sin reiniciar sesión ni tocar el escritorio.
El riesgo obvio es matar de más: el systemd de usuario, la barra, el audio o la
propia terminal desde donde se ejecuta el comando.

**Elegido.**

- Clasificar por **cgroup v2**, sin `ps` ni `pgrep` (que en esta máquina están
  tapados por busybox en `~/bin`): solo se mira `user.slice/user-<uid>.slice`.
- Se considera "arranca solo" la unidad cuyo proceso más viejo empezó dentro de
  la ventana (`LIBERAR_VENTANA`, 300 s) de un **ancla**: el `btime` del arranque
  o el inicio de una `session-*.scope` (cada login). Son las dos únicas cosas
  que se conservan sin discutir.
- Los `*.scope` (apps lanzadas a mano) son siempre candidatos; los `.service`
  viejos se respetan, y `liberar -s` baja también esos servicios con
  `systemctl --user stop` (no `kill`, así no los revive el `Restart=`).
- Nunca se toca la **cadena de ancestros de la terminal actual ni su subárbol**
  (si corre dentro de tmux, protege todo el servidor tmux): el resultado tiene
  que verse en la misma ventana.
- `~/.config/liberar/keep.conf` (regex contra cmdline, ejecutable y nombre de
  unidad) es el override humano; los patrones se evalúan **a nivel de unidad**:
  si un solo proceso de la unidad está protegido, no se para la unidad entera.
- `-n` lista y suma RSS antes de matar: es un comando destructivo, así que el
  antes/después se muestra siempre.

**Descartado.**

- `loginctl terminate-user` / `systemctl --user exit`: tira la sesión gráfica
  entera y no se puede ver el resultado.
- Filtrar por antigüedad del proceso o por nombre de app (`matar todo menos
  brave`): no distingue un servidor de usuario de una app abierta, y envejece
  mal.
- `pkill`/`killall` por patrón: mata procesos del sistema y de otras sesiones.

## 2026-10-19 — El crash se diagnostica solo y queda como ticket del rig

**Contexto.** El watcher de Omarchy (`omarchy-crash-watch`) avisaba el crash con
un toast "Click to diagnose with AI": el diagnóstico solo corría si el dueño
hacía click, y no quedaba ticket, traza ni evidencia. Si el aviso se perdía, el
crash se perdía con él. Se quiere que arranque solo y quede visible en el rig
para hacerle seguimiento.

**Elegido.**

- Un watcher propio (`linux/bin/omarchy-crash-autodiagnose`) reemplaza al de
  Omarchy por **drop-in de systemd**, para no editar `/usr/share/omarchy` (se
  pisa en cada `omarchy update`). Conserva la señal (journal `MESSAGE_ID` de
  systemd-coredump), el dedupe por programa, el filtro por usuario y el toggle
  `crash-capture-off`.
- Cada crash abre un **ticket `CRASH-<pid>-<epoch>`** en el proyecto `infra` y
  corre el diagnóstico con **`opencode run` headless** (el mismo agente que ya
  usa el rig), probando **solo modelos free** de OpenCode Zen en orden y pasando
  al siguiente ante 429. Cierra el ticket con evidencia, sesión y evento.
- El diagnóstico se desprende con `systemd-run --user` (unit transitorio) para
  sobrevivir a un reinicio del watcher.
- El método sigue en la skill `diagnose-crash`; el prompt la nombra en vez de
  duplicar pasos.

**Descartado.**

- Diagnóstico con Pi headless: los modelos free de Pi que responden son solo
  `opencode-go/longcat-2.5-preview-free` y `cat-jam-free` (el resto da 403
  `FreeTierError` o 400 "unavailable"), y las trazas de Pi no entran en el
  tablero de tickets del rig. OpenCode da muchos más modelos free y el ticket
  nativo del rig.
- Habilitar `pi-model-fallback` global: el fallback vive en el propio script
  (lista de modelos free), sin cambiar el comportamiento de todas las sesiones.
- Lanzar el diagnóstico en una silla tmux interactiva: nunca cierra sola, así
  que el ticket no se podría cerrar solo. `opencode run` headless sí termina.

## 2026-10-18 — Un worktree por agente, y dos flujos por proyecto

**Contexto.** Varios agentes trabajando en el mismo repo compartían carpeta y
rama: se pisaban archivos, un `git add -A` se llevaba trabajo ajeno y el árbol
quedaba sucio sin dueño (pasó en foldertinder: 55 archivos sin commitear en
`master`, dos stashes de "dead-batch" y un worktree viejo convivendo). El usuario
quiere que cada agente tenga su versión del código, pero sin imponer una rama de
desarrollo en proyectos donde no la necesita.

**Elegido.**

- `~/.pi/agent/worktrees.json` (versionado acá) declara el flujo de cada
  proyecto: `main` (base y merge en la rama principal), `developing` (base y
  merge en la rama de desarrollo) o `directo` (se edita en el lugar, sin
  worktree: dotfiles). Lo no listado usa `flujoPorDefecto = main`.
- `extensions/worktrees.ts` hace cumplir la regla: reglas en el system prompt de
  cada turno, bloqueo de `write`/`edit` y de los comandos bash que escriben en la
  copia principal, un worktree automático por subagente y la tool `worktree`
  (`abrir` / `lista` / `cerrar`, que mergea y limpia).
- La decisión pura (flujos, rutas, detección de comandos que escriben) vive en
  `extensions/lib/ramas.ts` con tests; lo impuro (git) en la extensión.
- `rig work new` lee la misma config para elegir la rama base.
- Escape hatch: `/worktrees libre` o `PI_SIN_WORKTREES=1`, para operaciones
  puntuales sobre la copia principal.

**Descartado.**

- Forkear el ejemplo `subagent` de pi para inyectarle worktrees: se
  desactualiza con cada versión de pi. En cambio, la extensión muta la llamada a
  `subagent` en `tool_call` y le cambia el `cwd` a cada tarea.
- Dejar la regla solo como consejo en el prompt: ya se probó y los agentes
  igual editan la copia principal cuando apura.
- Crear una rama `developing` nueva en `zentr0`: ya tiene `dev`, así que la
  config apunta ahí en vez de inventar historia.
- Un `.env`/flag por repo dentro de cada proyecto: la config central es un solo
  lugar para los dos consumidores (pi y rig).

## 2026-10-17 — Un solo visor del pensamiento y tareas con id

**Contexto.** El widget de `conversar.ts` mostraba el pensamiento en vivo, pero
pi también dibujaba el bloque nativo en el transcript: se leía dos veces. El
ritmo fijo no alcanzaba cuando el modelo pensaba muy rápido y los cortes
mostraban fragmentos de código o frases partidas. Además no había forma de
saber qué tarea estaba haciendo cada agente ni de reconstruir cómo llegó a la
solución.

**Elegido.**

- El widget es el único visor en vivo. El bloque nativo se oculta con
  `hideThinkingBlock: true`; `Ctrl+T` lo muestra si hace falta.
- Encabezado en una fila: `agente × título · id`. Se publica también en el
  título de la ventana para herdr/la barra.
- Ritmo adaptativo: 150 ms/palabra cómodo, 100 ms cuando la cola supera 40
  palabras; si igual sobra, se descartan las oraciones viejas.
- El texto pasa por helpers puros (`lib/pensamiento.ts`): saca fences, ANSI,
  URLs y code inline ilegible, y descarta fragmentos que terminan en conector.
- Las tareas viven en `rig.ts`: id `T-XXXXXX`, título automático, trace de
  pedidos, herramientas, resultados y pensamientos, más el enlace a la sesión
  completa. Continuaciones cortas se anexan a la tarea; un pedido distinto abre
  otra.
- Los helpers viven en `extensions/lib/` (sin `index.ts`) para que pi no los
  cargue como extensión.

**Descartado.**

- Frenar el render nativo del pensamiento: pi no expone una velocidad de
  streaming; el widget es la única capa que se puede dosificar.
- Copiar el texto completo del pensamiento a `tareas.json`: duplicaría la
  sesión y crecería sin control. Se guarda un resumen por mensaje y el enlace
  al archivo de sesión.
- Que el modelo tenga que crear la tarea a mano en cada turno: costo y olvidos.
  Se captura sola; el modelo solo la renombra o anota si hace falta.

## 2026-10-18 — El cerebro de voz pasa de Pi a Hermes

**Contexto.** Omar (el asistente de voz, wake word "omar") resolvía lo que no
era comando fijo con Pi headless (`voice-pi`) a través de `pi_shim.py`. El
usuario usa Hermes como harness y quiere que Omar corra ahí, con el mismo
modelo que ya usa Hermes (`deepseek-v4.1-flash` de opencode-go), cubierto por
su plan y sin costo por token.

**Elegido.**

- `linux/bin/voice-hermes`: `hermes -z` dentro de `linux/voice/pi-brain/`, con
  `--toolsets terminal` (muchos menos esquemas: el prompt baja de ~46 KB a lo
  mínimo) y el `AGENTS.md` del cerebro, que Hermes ya carga por CWD.
- `pi_shim.py` apunta a `voice-hermes` por defecto. `VOICE_BRAIN_BIN` manda;
  `VOICE_PI_BIN` queda por compatibilidad con configs viejas.
- `voice think` y `omar ask` llaman a `voice-hermes`. `voice-pi` sigue
  existiendo como variante explícita.
- El guard de comandos destructivos (`pi-brain/guard/`) se comparte: los
  symlinks de `omarchy`/`systemctl`/`reboot` siguen haciendo la confirmación
  hablada sin importar el harness.
- El modelo no se fija en el script: es el default de `~/.hermes/config.yaml`,
  para que haya una sola fuente de verdad. `VOICE_HERMES_MODEL` y
  `VOICE_HERMES_PROVIDER` permiten pisarlo.
- `voice-pi-shim.service` conserva el nombre (histórico) para no migrar links,
  timers ni la config de OmniVoz.

**Descartado.**

- `deepseek-v4.1-flash-free` de OpenCode Zen: es el mismo modelo gratis, pero
  su capa gratuita sólo atiende al cliente de OpenCode (`HTTP 403: free tier
  can only be used from within OpenCode` desde Hermes y desde `pi`). No es una
  opción real fuera de esa app.
- Renombrar el servicio a `voice-brain-shim.service`: obliga a migrar enlaces y
  unidades por un nombre, sin ganar nada funcional.
- Un script genérico con ramas Pi/Hermes: más código para una sola decisión de
  harness. Si mañana vuelve a cambiar, se agrega otro `voice-*` y se cambia
  `VOICE_BRAIN_BIN`.

## 2026-10-18 — Pi arranca en pensamiento `low`

**Contexto.** El nivel de razonamiento quedaba en `high` al reanudar sesiones y
para sesiones nuevas, lo que encarece y demora el trabajo de todos los días sin
que el usuario lo haya pedido.

**Elegido.** `defaultThinkingLevel: "low"` y
`modelThinkingLevels: {"deepseek/deepseek-flash": "low"}` en
`linux/pi/agent/settings.json`. Las sesiones ya abiertas conservan su nivel
hasta que se cambie con `/thinking`; las nuevas arrancan en `low`.

**Descartado.** Forzar `--thinking low` en cada invocación: no cubre las
sesiones interactivas y duplica la config.

## 2026-10-18 — El cerebro de voz arranca gratis

**Contexto.** El usuario quiere empezar desde lo más barato (gratis) y pagar
sólo si no alcanza, nunca al revés. Hermes venía con
`deepseek-v4.1-flash` (opencode-go): barato, pero pago.

**Elegido.**

- En `~/.hermes/config.yaml`: primario **`cat-jam-free`** y cadena de respaldo
  **`beam-free`** y **`longcat-2.5-preview-free`**, los tres gratis del plan
  opencode-go. Omar hereda ese default.
- Medidos con tareas reales del cerebro (foco, ventanas del workspace 5,
  volumen, multi-paso en dry-run): `cat-jam-free` y `beam-free` 3–5 s y
  `longcat-2.5-preview-free` 13–18 s; los tres usan herramientas y aciertan.
  `cat-jam-free` primario por balance calidad/latencia, `beam-free` de respaldo
  rápido y `longcat` por si hace falta más cabeza.
- `scripts/verify/cerebro.sh` falla si el modelo primario o un respaldo dejan
  de ser gratis: la regla "nunca pagar primero" queda chequeada.
- `VOICE_HERMES_MODEL` no está fijado: cambiar de modelo es editar la config de
  Hermes, un solo lugar.

**Descartado.**

- `deepseek-v4.1-flash` como primario: más capaz, pero es exactamente el orden
  que el usuario no quiere.
- Un respaldo pago: gastaría solo, sin que el usuario lo pida. Si los gratis no
  alcanzan, se decide entonces, no de antemano.

## 2026-10-19 — La actividad de los agentes va a una bodega unificada (NDJSON + SQLite)

**Contexto.** Los agentes se hablan, abren tickets y dejan eventos, pero todo
queda en archivos sueltos sin IDs estables entre sí: el buzón de correo
(`~/.local/state/rig/correo`), el feed de eventos, los dos tableros de tickets
(rig y pi) y las sesiones de pi. Se quiere guardar todo junto para poder subirlo
alguna vez a la nube y leerlo desde varias aplicaciones.

**Elegido.**

- Un log **append-only en NDJSON** (`~/.local/share/rig/db/unificado.ndjson`) como
  fuente de verdad y unidad de réplica: idempotente, con id determinista por
  hecho, sin cursores que se rompan cuando un archivo muta (el buzón reescribe
  `leido` in-place y los tickets se reescriben enteros, así que se releen enteros
  y se deduplica por id).
- **SQLite reconstruible** (`rig.db`, con FTS5) como vista de consulta, no como
  fuente. Se puede borrar y regenerar del NDJSON.
- Los archivos originales **siguen siendo la fuente de escritura**: no se reescribe
  rig para que use una base.
- `sync` se corre al mandar un mensaje, al tocar un ticket y desde un timer
  opcional de systemd; no hay daemon.
- Contenido crudo de sesiones y `opencode.db` quedan afuera: se indexa metadata
  y se referencia la ruta.

**Descartado.**

- API HTTP propia, outbox/CDC y esquema cloud desde el arranque: no hay
  consumidor todavía, y se agregan después sin cambiar la ingesta.
- Ingerir `opencode.db` (3,6 GB): acopla a un esquema ajeno y cambiante, y es la
  fuente de menor valor para este objetivo.
- Postgres/Supabase ya: SQLite no sirve multi-escritor en la nube, pero el NDJSON
  es el formato de importación cuando haga falta. Ver `docs/bodega-agentica.md`.
