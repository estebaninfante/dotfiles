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
  timers ni la config de Omar.

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

## 2026-10-19 — El cerebro de voz vive con la sesión gráfica

**Contexto.** El 2026-10-19 a las 04:25 la sesión gráfica se reinició (logout/
login) y `voice-pi-shim.service` no volvió: quedó `inactive (dead)` con el
proceso terminado por SIGTERM en el teardown. Estuvo 9 horas caído y Omar
contestaba "no pude resolver eso" — el `fetch` al `127.0.0.1:11435` fallaba y el
error solo se logueaba. Dos causas juntas: la unidad era `WantedBy=
default.target` (sin `PartOf=graphical-session.target`, así que el reinicio de la
sesión no la levantaba) y `Restart=on-failure` no revive un TERM externo.

**Elegido.**

- `After=`/`PartOf=`/`WantedBy=graphical-session.target`, igual que
  `voice-daemon`: el cerebro vuelve solo cuando vuelve la sesión.
- `Restart=always` + `StartLimitIntervalSec=0`: si el proceso muere por una
  señal externa, systemd lo levanta; sin tope de reintentos.
- La unidad entra en `enabled-laptop.txt` para que `install-user-units.sh` la
  enlace al repo (symlink). Antes era una copia suelta y driftaba en silencio.
- `scripts/verify/cerebro.sh` ya avisaba del drift del `AGENTS.md` del cerebro;
  se copió el del repo. La copia viva decía `omar ticket …`, que no existe:
  el CLI de tickets es `omar-hub`.

**Descartado.**

- Un healthcheck externo con timer que reinicie el puente: systemd ya puede
  hacerlo desde la unidad, sin proceso extra ni latencia.
- Dejar el puente en `default.target` y atarlo por `Wants=` desde `omar-listen`:
  mezcla ciclo de vida de sesión con ciclo de vida de usuario.

## 2026-10-19 — Cortar la voz la calla, no la degrada

**Contexto.** Con la tecla física de Windows `present-remote toggle` cierra a
Omar, que manda `voice stop`. El daemon hacía `pkill -f pw-play` y el
`synth_and_play` tomaba el playback muerto como "falló el motor", así que
reintentaba la MISMA frase con piper y después espeak: en vez de silencio se
oía otra voz, peor. Además el `pkill` por patrón se llevaba earcons, chimes y
cualquier otro `pw-play` (y hasta un shell cuyo comando mencionara el patrón).

**Elegido.**

- Un contador de generación (`_play_epoch`) que sube en `stop`; `_play` lo mira
  y devuelve `cancelled` en vez de `error`. En `synth_and_play`, `cancelled`
  corta la cadena de motores; `error` sigue cayendo a piper/espeak como antes.
- Se chequea el epoch antes de sintetizar y antes de reproducir: si el corte
  llega durante la síntesis, la frase se descarta (no suena después).
- El playback se corta por **PID** (`_current_play.terminate()`), no con
  `pkill -f`. `voice repeat` usa un patrón anclado (`^pw-play .*Voice TTS`).

**Descartado.**

- `pkill -f "Voice TTS"`: más acotado que `pw-play`, pero seguía matando
  procesos ajenos que mencionaran el texto (medido: mató el shell del test).
- Marcar el corte con un archivo con vencimiento: ventana arbitraria, decide
  por tiempo lo que ya se sabe por generación.

## 2026-10-19 — Cancelar la voz responde en el acto (y calla aunque Omar esté apagado)

**Contexto.** Medido el recorrido de la tecla de Windows: `voice-key-listener`
tenía un antirrebote de 800 ms que **descartaba la segunda pulsación**, así que
"cerrar y que se calle" no hacía nada hasta apretar otra vez. `present-remote`
decidía con `qs ipc` (dos intentos, ~60-150 ms), cerraba la UI antes de avisar
al oído, y la señal iba por `systemctl kill` (un proceso extra). Peor: si Omar
estaba apagado y hablaba un aviso de otro agente, la tecla **prendía a Omar** y
la voz seguía sonando; había que apretar de nuevo para callarla.

**Elegido.**

- Una pulsación, una acción: se elimina el antirrebote por tiempo; el "down"
  repetido al mantener ya lo cubre el flag por pulsación.
- La píldora se lee de `pill-open` (el archivo que publica el propio QML y que
  el glow ya usa). `qs ipc` queda como respaldo si el archivo no existe.
- Si no hay Omar activo pero `speaking.json` está vigente, la tecla/`Escape`
  cortan el audio (`voice stop`) en vez de prender a Omar.
- Cerrar: `SIGUSR2` por `listen.pid` + `kill(2)` (validando la línea de
  comandos del PID) y `voice stop` en paralelo; UI y limpieza de PTT después,
  con topes cortos (1,0 / 0,6 / 0,3 s) para no trabar la próxima pulsación.

**Descartado.**

- Sólo adelantar la señal y esperar al loop de Omar: medido ~80 ms extra; el
  `voice stop` directo baja la pulsación→silencio a ~60 ms.
- Depender de `status.json` para saber si Omar está despierto: lo publica
  también el dictado y llega con retardo; `pill-open` es el estado de la
  superficie que el usuario ve.
- Un antirrebote más corto (100-200 ms): sigue perdiendo pulsaciones rápidas y
  no aporta nada que el flag de pulsación no resuelva.


## 2026-10-19 — El presupuesto de RAM se mide y se verifica, no se estima

**Problema.** El core residente de la máquina (sistema + escritorio + voz +
visión) se iba a ~5,8 GB sin que nadie pudiera decir cuánto pesaba cada parte ni
cuándo se pasaba del límite. Las discusiones sobre "Omar pesa demasiado" se
hacían con `free -h`, que no distingue core de satélites ni memoria privada de
compartida.

**Decisión.**

1. `linux/bin/res-budget` mide con **PSS** (`smaps_rollup`), no con RSS: RSS
   cuenta dos veces cada página compartida y hace que dos procesos que comparten
   los mismos pesos inflen el número. Clasifica por la **unidad systemd del
   cgroup**, que es más fiable que adivinar por `cmdline`.
2. El presupuesto aplica sólo al **core** (kernel + sistema + escritorio + voz +
   visión). Los satélites (agentes, editores, navegadores, servidores de
   desarrollo) son de demanda y no cuentan.
3. `res-budget.timer` lo corre cada 15 min y avisa por notificación si el core
   excede el límite. `RES_BUDGET_MB` lo cambia sin tocar código.

**Medido la primera vez que corrió.** Core 5,8 GB de 8,2 GB: kernel 564 MB,
escritorio 399 MB, sistema 81 MB, visión 516 MB y **voz 4,3 GB (74 % del core)**.
El límite no lo rompe el core: lo rompen los satélites.

**Descartado.**

- Medir con RSS: sobrecuenta la memoria compartida y no permite comparar entre
  configuraciones.
- Presupuesto sobre "toda la RAM usada": mezcla core con trabajo del usuario y
  no dice nada accionable.
- Un umbral en `res-reap` en vez de un medidor propio: `res-reap` mide
  `MemAvailable`, que es un síntoma, no una causa.
