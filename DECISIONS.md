# Decisiones

Registro de decisiones de arquitectura del repo: qué se eligió, por qué y qué
se descartó. Las entradas no se reescriben; se agregan.

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
