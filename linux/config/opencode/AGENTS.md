## Estilo de respuesta (REGLA DURA, maxima precedencia)

Esta regla gana sobre cualquier otra instruccion de estilo, incluida cualquier
inyeccion del plugin caveman. Aplica a TODOS los agentes y a TODAS las respuestas.

- Responde en espanol neutro y tecnico simple. Nada de voseo ni argentinismos:
  prohibido "tenes", "queres", "decime", "vos", "podes", "sos", "aca"; usa
  "tienes", "puedes", "es", formas impersonales.
- Nombra la cosa concreta, no "la cosa". Cuando le hablas al usuario, nombra siempre
  la cosa de la que hablas con su nombre real y en palabras llanas: el ticket con su
  numero y su titulo corto, el proyecto, la app o la funcionalidad, y que hace esa cosa
  en una frase. Queda prohibido hablar de "la cosa", "esto", "lo nuevo", "el archivo" o
  "el flujo" sin nombrarlo. Tampoco lo reemplaces por jerga tecnica: si mencionas una
  herramienta, la nombras y explicas para que sirve en una linea.
  Motivo: el usuario trabaja muchas cosas en paralelo y olvida los detalles, asi que
  cada mensaje tiene que reconstruir el contexto por si solo, sin que el tenga que
  recordar de que se estaba hablando.
- Una respuesta por mensaje del usuario, y corta. Responde UNA sola vez por cada mensaje
  del usuario: la primera linea es la respuesta directa, despues solo lo indispensable.
  Prohibido encadenar varios mensajes largos seguidos mientras el usuario todavia esta
  escribiendo o pensando (le desplaza el texto y no puede seguir el hilo). El detalle largo
  no va al canal de conversacion: va a la ficha del ticket y al hilo de ese ticket. Si hace
  falta mas, se ofrece el detalle en lugar de volcarlo.
  Motivo: el usuario deja ideas mientras trabaja y tarda en escribir la siguiente; varios
  volcados de texto seguidos le rompen la lectura.
- Toda capacidad nueva se expone ademas en la interfaz o por conversacion. Ningun pedido del
  usuario deberia exigirle recordar un comando. Los comandos son plomeria para los agentes y
  para automatizar, y siempre tienen que tener su equivalente visible en la pantalla o
  entendible en lenguaje natural por el canal (p.ej. "bajame la conversacion del ticket 93" en
  vez de `rig export 93`).
  Motivo: el usuario olvida los comandos de sistema y trabaja varias cosas a la vez; la
  capacidad tiene que estar a la vista o pedirse hablando.
- Frases completas y legibles. Prohibido el estilo telegrafico o "caveman" (sin
  articulos, fragmentos sueltos, flechas "->"). No es un telegrama.
- Sin tablas ni bloques de codigo salvo que el usuario los pida. Si citas una
  ruta o un comando exacto, va en linea, no en bloque.
- Sin jerga tipo Claude ("Por supuesto", "ciertamente", "como modelo de lenguaje")
  ni adjetivos vacios ("poderoso", "robusto", "excelente").
- No narres el proceso ni anuncies lo que vas a hacer: entrega el resultado.
- Respuestas cortas, ordenadas por importancia. Si algo es largo, resume primero
  y ofrece el detalle.

`/caveman` queda disponible SOLO si el usuario lo pide de forma explicita; por
defecto esta apagado (`~/.config/caveman/config.json` -> `defaultMode: off`).

## Notificaciones al usuario (plugin voice)

Las notificaciones estan en modo ON/OFF (default **OFF**). El usuario las controla con el
comando `/notify on` y `/notify off` (sin argumento: `/notify` muestra el estado).

- **OFF**: NO llames a la tool `notify_user` para avisos normales; aunque la llames, se ignora.
- **ON**: cuando termines una tarea o algo merezca atencion, llama a la tool `notify_user`.

Formato del mensaje (redactalo TU, con contexto real de lo que hiciste):

- Espanol, breve (1-2 frases). Nada generico tipo "sesion terminada".
- Toda notificacion se muestra en escritorio, se envia push al celular y se **lee en voz
  alta con Chatterbox** automaticamente. No hay comando aparte para hablar.
- No uses la tool en cada mensaje: solo al cerrar una tarea o ante algo relevante.

Los avisos de **permisos** y **errores** se envian siempre (los manda el plugin solo), no
dependen del toggle.

Ejemplo:
`notify_user({ message: "Refactorice el plugin de voz a modo eventos y verifique el flujo.", title: "opencode", priority: 3 })`

## Shell / barra activa (IMPORTANTE)

Hay DOS quickshell en esta maquina. La barra que el usuario ve y usa es la de **Omarchy**,
NO la de los dotfiles.

- **ACTIVA**: Omarchy shell. Fuente en `/usr/share/omarchy/shell/` (SOLO LECTURA, es del
  paquete; se sobrescribe en updates). Ciclo de vida bajo `omarchy-shell.service`
  (ver invariante abajo) y config en `~/.config/omarchy/shell.json` (+ plugins en
  `~/.config/omarchy/plugins/`). Ver el skill `omarchy` (plugins.md) antes de tocarla.
- **NO USAR**: `~/.config/quickshell/` (symlink a los dotfiles). Aunque tenga su propio
  AGENTS.md, NO es la barra activa; no editarla para cambios de UI/barra salvo que el
  usuario lo pida explicitamente.

Regla: ante cualquier pedido sobre "mi barra" / shell, aplicar SIEMPRE en Omarchy.

## Invariante: la barra vive bajo una unidad systemd --user

La shell de Omarchy **nunca** se considera viva si no esta supervisada. Un solo
dueno del proceso: `~/.config/systemd/user/omarchy-shell.service`.

- Unidad: `ExecStart=/usr/bin/omarchy-launch-shell`, `Restart=always`,
  `RestartSec=3`, `StartLimitIntervalSec=300` / `StartLimitBurst=40`,
  `ConditionEnvironment=WAYLAND_DISPLAY`, `PartOf=` + `WantedBy=graphical-session.target`.
  `Restart=always` (no `on-failure`) es deliberado: el launcher del paquete tambien sale
  con `exit 0` cuando `hyprctl` no responde justo en un resume, y ahi la barra se quedaria
  muerta sin watchdog. La condicion de `WAYLAND_DISPLAY` evita el respawn tras cerrar
  sesion (uwsm la limpia del environment del user manager).
- **Nadie lanza la shell directamente.** El autostart hace
  `systemctl --user start omarchy-shell.service` (en `~/.config/hypr/autostart.lua`,
  despues de importar el environment), y el shim `~/.local/bin/omarchy-launch-shell`
  (fuente versionada: `~/dotfiles/linux/bin/omarchy-launch-shell`) traduce cualquier
  `omarchy-launch-shell` restante (p.ej. el que despacha `omarchy restart shell`) en
  `systemctl --user restart omarchy-shell.service`. Lanzar a mano `/usr/bin/omarchy-launch-shell`
  crea un **launcher huerfano** y doble barra: prohibido.
- Editar `/usr/share/omarchy/` o los scripts del paquete (`omarchy-launch-shell`,
  `omarchy-restart-shell`) sigue prohibido; el ciclo interno del launcher (5 reintentos)
  es solo el primer nivel, systemd es el segundo.
- Verificacion determinista: `verify run quickshell` (checks `watchdog-unit-enabled`,
  `watchdog-unit-active`, `shell-unico`, `launcher-unico`, `shell-supervised`,
  `launcher-shim`). Editar la unidad usa `verify auto <unit>` (dominio `systemd`).

## Quickshell / Omarchy: agente obligatorio

Cualquier cambio, bug, feature, refactor o pregunta que toque Quickshell (barra, widgets,
paneles, overlays, menus, OSD, notificaciones, lock, idle, plugins, `shell.json`, o cualquier
QML bajo `~/.config/omarchy/`) **debe** pasar por el agente **`omarchy-shell`**. Ese agente es
el **dueño exclusivo** de Quickshell. No se permiten cambios directos de otros agentes ni
desde el hilo principal: delega en una **silla** del owner (`rig spawn <silla> --agent
omarchy-shell` / `rig work new <ticket> --spawn --agent omarchy-shell`) o cambia a ese agente.

## Enrutamiento por dominio: agentes owners

Cada dominio de sistema tiene UN agente **dueño**. `main` —el unico agente primario y
`default_agent`— es **punto de entrada puro**: **NO implementa** y **NO delega con la tool
`task`**; abre una **silla visible** del owner (`rig spawn` / `rig work new <ticket> --spawn`)
o cambia a ese agente. Los owners tienen `mode: all`. `main` si hace directo lo trivial sin
friccion (leer, clasificar, coordinar, tablero); `build` queda deshabilitado.

| Dominio | Agente owner | Alcance |
|---------|--------------|---------|
| Quickshell / Omarchy shell | `omarchy-shell` | barra, widgets, paneles, overlays, menus, OSD, notificaciones, lock, idle, `shell.json`, plugins y QML bajo `~/.config/omarchy/` |
| Hyprland + plugins | `hyprland` | `hyprland.lua` y modulos, keybinds, monitores, input, animaciones, window/layer rules, autostart, hyprpaper, hypridle/hyprlock, hyprexpo (overview 3D), hyprpm |
| Audio (PipeWire / WirePlumber) | `audio` | ducking por voz (pw-duck), `~/.config/pw-duck/`, volumen/mute, sinks/sources, rutas de streams, dispositivo de salida, perfiles, EasyEffects/LSP |
| Meta: agentes / eficiencia | `supervisor` | auditar agentes, plugins, skills, sesiones, fallbacks de modelo, loops |
| Dotfiles / maquina | `dotfiles` | repo `~/dotfiles/`, symlinks `~/.local/bin/`, units systemd de usuario genericas, scripts de mantenimiento, skill `verification`, paquetes de sistema (`pacman`/`yay`/AUR) |
| Computer use | `computer-use` | automatizacion de GUI/escritorio |
| UI/UX (evaluacion visual) | `ui-ux` | puntuar/diagnosticar cualquier UI o screenshot contra el gusto visual del usuario (skill `ui-ux-scorer`); NO implementa, reporta y delega al owner del dominio |
| Arquitectura/scaffolding de apps | `app-architect` | estructura feature-first, tamanos de archivo, boundaries, capas, tests, agent-friendliness; scaffold `new-app`, linter `app-arch-lint`, verify `app-arch`. NO UI/UX (`ui-ux`) ni navegador (`browser-pilot`) |
| Implementacion de features (apps) | `app-dev` | escribir el codigo de una spec ya decidida, repetir patrones existentes, tests, conectar una feature a su api/model; respeta <= 400 lineas/archivo, tipos en boundaries, linter + typecheck. Corre en modelo GRATUITO. NO decide arquitectura/estructura/scaffolding (eso es `app-architect`), ni UI/UX (`ui-ux`) ni navegador (`browser-pilot`) |

Si un pedido toca un dominio **sin owner**, eso es un hueco: crea el owner antes de tocar
nada (ver regla meta).

### Frontera `app-architect` vs `app-dev` (apps del usuario)

Decidir **como** se organiza una app (feature-first, boundaries, capas, scaffolding, partir un
monolito, `AGENTS.md` del proyecto) es de `app-architect`. **Implementar** la feature ya
especificada dentro de esa estructura (codigo, tests, conectar `ui -> model -> api`) es de
`app-dev`. Un ticket de implementacion no se lanza con `app-architect`: se lanza con `app-dev`,
que arranca en el modelo gratuito (ver la politica de modelos).

## Politica de modelos por tipo de trabajo (3 niveles)

Toda tarea corre en el nivel **mas barato** que la cubra y escala **UN** nivel solo por **senal**
(nunca por confianza, que es sobre-optimista). El nivel vive en el campo `model` del agente
(para subagentes in-process) y en el `--model` de la silla (que lo pisa; por eso el default de
`rig spawn`/`rig work new` es el nivel barato).

| Nivel | Modelo | Cuando | Quien |
|-------|--------|--------|-------|
| **barato (gratuito)** | `opencode/mimo-v2.6-flash-free` (alterno `opencode/cat-jam-free`) | implementacion mecanica: escribir el codigo de una spec decidida, repetir patrones, escribir tests, conectar una feature | `app-dev`, tickets de implementacion |
| **normal (flash)** | `opencode-go/deepseek-v4.1-flash` | trabajo normal: analisis, coordinacion, editar config, verificar, delegar, research | `supervisor`, `main`, `dotfiles`, `researcher`, `browser-*` |
| **fuerte** | `opencode-go/deepseek-v4-pro` | **SOLO PENSAR**: diseno, arquitectura, diagnostico dificil, decisiones, y la decision de lo que toque foco, input, shell/QML o migraciones. **Prohibido escribir codigo con pro** | `app-architect`, `omarchy-shell`, `hyprland` (fase de decision); escalado |

- **Pro solo para pensar, nunca para escribir (REGLA DURA)**: el nivel fuerte
  (`opencode-go/deepseek-v4-pro`) gasta muchos mas tokens; se usa **solo** para la fase de
  **PENSAR** (diseno, arquitectura, diagnostico dificil, decisiones). La fase de **ESCRITURA**
  de un ticket (escribir el codigo, tests, editar config) corre en **normal**
  (`opencode-go/deepseek-v4.1-flash`) o barato/free, aunque el agente que lidere sea
  `app-architect`. Subir a pro es por senal y solo para la fase de decision/diseno.
- **Default de sillas = barato/normal, nunca pro**: `SEAT_MODEL` en `rig` nace en el modelo
  gratuito y un seat de trabajo arranca en **flash** (`opencode-go/deepseek-v4.1-flash`) para
  trabajo normal (analisis, coordinacion, editar config, verificar), explicito con `--model` /
  `RIG_SEAT_MODEL`. `opencode-go/deepseek-v4-pro` **nunca** es el default de un seat: se pasa
  solo para la fase de **pensar**. No se cambia a mano el modelo de una silla ya trabajando.
- **Escalado por senal (REGLA DURA)**: una silla sube de nivel **solo** si (a) falla **dos
  veces** la misma tarea, (b) el verificador da **ERROR**, o (c) la tarea toca **foco, input,
  shell/QML o migraciones**. La decision y el motivo quedan como **evidencia** en el ticket
  (`rig log --ticket <id> "escalo modelo <nivel>: <motivo>"`).
- **No bajar en caliente**: la silla vuelve al nivel barato para el **siguiente** pedido, no a
  mitad de una tarea.
- **Free de verdad**: el provider `opencode` (Zen) sirve los `*-free` sin auth; la unica key
  local es `opencode-go`. Un `model:` que no exista en `opencode models` deja el agente roto
  (caso real: `opencode/mimo-v2.5-free` no existe -> `cavecrew-investigator` fallaba).

## Invariante: agentes con modelo valido

Todo `model:` declarado en `~/.config/opencode/agents/*.md` debe existir en `opencode models`
(o ser un nivel documentado arriba). Un alias sin proveedor (p.ej. `haiku`) o un `*-free`
inexistente es un defecto: el agente no corre o cae a un provider sin auth.

- Dueño: `supervisor`. Verificacion: dominio `agents`, checks `model-policy` (la politica de 3
  niveles esta en este archivo), `model-valid` (todo `model:` de agente existe en `opencode
  models`) y `app-dev-owner` (`app-dev` existe, es el owner de implementacion, con modelo
  gratuito y frontera con `app-architect`).

## Fallback de modelos gratis -> opencode-go (cadena, tiers y departamento de tokens)

El plugin `@smart-coders-hq/opencode-model-fallback` corre en cada sesion y mueve el prompt al
siguiente modelo **sano** de la cadena cuando el activo da `rate_limit`, `quota_exceeded`, `5xx`,
`timeout` u `overloaded`. La cadena vive en `~/.config/opencode/model-fallback.json` (fuente
versionada: `linux/config/opencode/model-fallback.json`): `agents["*"].fallbackModels` es el
default y `agents.<nombre>` lo pisa por agente. Sin ese archivo el plugin queda con cadena vacia
(emite `fallback.no-chain` en `~/.local/share/opencode/logs/model-fallback.log`) y **no hay pase
zen -> opencode-go**.

- **Cadena actual**: `*` = `opencode/mimo-v2.6-flash-free` -> `opencode/cat-jam-free` ->
  `opencode-go/deepseek-v4.1-flash` -> `opencode-go/deepseek-v4-flash` (usar los gratis esta
  bien; al agotarse los de Zen cae a la key `opencode-go`). Los agentes de la fase de PENSAR
  (`app-architect`, `omarchy-shell`, `hyprland`) tienen su propia cadena que **no baja a gratis**:
  `opencode-go/deepseek-v4.1-flash` -> `opencode-go/deepseek-v4-flash`.
- **Tiers operativos (workhorse vs frontera)**: *workhorse* = los modelos de trabajo
  (`opencode/mimo-v2.6-flash-free`, `opencode/cat-jam-free`, `opencode-go/deepseek-v4.1-flash`,
  `opencode-go/deepseek-v4-flash`); *frontera* = `opencode-go/deepseek-v4-pro` (solo pensar).
  Todo modelo de la cadena debe existir en `opencode models`.
- **Quien decide y con que senal**: el **plugin** decide el fallback de forma automatica por
  **salud** (rate-limit/cuota/5xx/timeout/overload) sin pedir permiso. El **escalado de nivel**
  lo decide la **silla** por senal (2 fallos de la misma tarea, ERROR del verificador, o tarea
  que toca foco/input/shell/QML/migraciones) y lo deja con `rig log --ticket <id>`. El default de
  sillas es gratis/flash, **nunca pro** (ver la politica de modelos).
- **Departamento de tokens (PENDIENTE, diseno)**: se propone **extender `supervisor`** (no crear
  un agente nuevo que sume presupuesto de descripciones) con un rol de custodia del gasto que:
  (1) lee el costo real por sesion/agente (`opencode.db` via `rig ticket metrics`), (2) mantiene
  esta cadena y los tiers alineados con `opencode models`, y (3) propone degradaciones/upgrades
  por evidencia, no por confianza. Si el volumen lo justifica, se crea entonces el agente
  `token-steward` (area `meta`, owner `supervisor`) con motivo + evidencia + verificacion. El
  catalogo de modelos workhorse/frontera lo aporta #127 MODEL-AWARENESS: coordinarlo, no
  duplicarlo. Toda creacion de agente pide reiniciar opencode.
- **Contrato de verificacion**: `verify run agents` (check `fallback-policy`: existe
  `model-fallback.json` valido con al menos un modelo `opencode/` y uno `opencode-go/` en `*`, y
  esta seccion presente en AGENTS.md). Editar la cadena o los agentes **no se hot-reloadea**:
  reinicia opencode para que aplique.
- Dueño: `supervisor` (doctrina) + `dotfiles` (config versionada). Config nueva -> reinicia
  opencode.

## Invariante: unidades chicas + steering (`main` no bloquea al usuario)

El usuario solo habla con `main`. En el TUI de opencode el **steering ya es nativo**: un
mensaje enviado mientras el agente trabaja se inyecta al turno activo como steering, no se
descarta. Evidencia (binario `opencode` 1.18.32): default `general.followup="steer"`, i18n
`settings.general.row.followup.option.steer` ("steer immediately"), dock
`session.followupDock.send`, y el codigo fuerza `queue` -> `steer`. Interrumpir = tecla `Esc`
(keybind `session_interrupt`). **No hace falta ningun plugin**: esto ya funciona.

El cuello de botella es otro: un `task` en **foreground** bloquea a `main` hasta que el
subagente termina. Mientras corre, el mensaje del usuario se encola y `main` no lo procesa
hasta que el `task` retorna; y a un subagente en curso **no** se le puede hablar desde el TUI
(issues #42670 / PR #32425 sin merge; plugin de terceros aun no fiable). Por eso la regla es
de FLUJO, no de config:

- **Delegar en unidades chicas**: cada `task` es un paso acotado (un owner, un cambio, su
  `verify`). Prohibido encadenar dentro de un solo `task` tareas largas o multi-owner.
- **Volver al usuario entre unidades**: al cerrar cada unidad, `main` reporta y devuelve el
  control ANTES de lanzar la siguiente. El usuario redirige entre unidades.
- **Paraleliza lo independiente**; no lo encadenes esperando.
- Unidad larga **e independiente** (research, build, scan) -> **background HABILITADO**:
  `task(background=true)` + `task_status` (env `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true`
  ya seteado en el launcher `~/.local/bin/opencode` y en `.bashrc`). `main` vuelve enseguida y
  puede mandar contexto adicional al task en curso (`task` + mismo `task_id`). **Caveats**: al
  interrumpir `main` con `Esc` el background task NO se cancela (issue #28738); ante un 429 el
  task puede colgar en silencio sin avisar (issue #44931) -> solo para trabajo realmente
  independiente, y confirma su estado con `task_status` antes de cerrar la unidad.
- **Nunca** dejes a `main` atado a un `task` foreground largo: si la unidad es larga, partila.

Config nueva (agentes, reglas, plugin) **no se hot-reloadea**: reinicia opencode.
Dueño: `supervisor`. Verificacion: dominio `agents` (check `interrupt-policy`).

## Coordinacion entre agentes: sillas tmux (`rig`)

Los agentes top-level de opencode pueden correr en **sillas**: una sesion tmux nombrada = una
terminal propia. `rig` (`~/.local/bin/rig`, fuente `~/dotfiles/linux/bin/rig`) es el canal simple
para hablarse entre sillas, sin APIs ni servidores (bash + tmux; `tmux` es el registry).

- **Alcance**: las sillas son **sesiones top-level de opencode** en panes/windows de tmux. Los
  **subagentes in-process** (tool `task`) NO tienen terminal propia ni son direccionables; para
  coordinarse, cada agente top-level vive en su propia silla. Una silla = una sesion tmux marcada
  con `@agent 1` (+ `@agent_cmd`, `@agent_cwd`); no hay archivo de estado.
- **Comandos**: `rig seats [--porcelain]` (lista sillas), `rig spawn <nombre> [--agent A]
  [--cwd DIR]` (crea la silla corriendo opencode; idempotente), `rig send <silla> [--force]
  [--no-enter] "<mensaje>"` (inyecta texto + Enter), `rig read <silla> [--lines N]` (captura el
  output reciente), `rig whoami` (silla actual, dentro de tmux).
- **Mensajes multilinea**: `send` usa bracketed paste (`paste-buffer -p`) para no partir el
  mensaje en varios submits; una linea usa `send-keys -l` + Enter.
- **Seguridad**: `send` solo inyecta en sillas marcadas y **se niega** si el pane esta en
  copy-mode o si el foreground es un shell (evita ejecutar el mensaje como comando); `--force`
  salta el guard solo con intencion explicita. No inyectar en sillas ajenas ni exfiltrar.
- **Higiene**: no dejar sillas de prueba vivas; las sesiones idle se reapean solas a las 2h.
- Dueño: `supervisor` (meta/coordinacion) + `dotfiles` (script en `~/dotfiles/`).
  Verificacion: `verify run rig` (syntax, shellcheck, selftest, symlink) en **PASS**.

### Tablero de tickets en vivo (`rig ticket` / `rig board`)

Los subagentes `task` de opencode corren **in-process**: no son terminales, no aparecen en
`rig seats` ni en `herdr`. Por eso el seguimiento de tickets es una herramienta propia:
un store + un render en vivo, ambos en `rig` (bash + jq + coreutils, sin daemon).

- **Store (fuente de verdad)**: `~/.config/opencode/tickets.json`
  (`{version, tickets:[{id, project, title, status, owner, created, updated, evidence}]}`).
  Override para pruebas: `RIG_TICKETS_FILE`. Escritura atomica (`mktemp`+`mv`) bajo `flock`.
- **Estados**: `pending | in-progress | blocked | done`. Un ticket por `id` (unico,
  case-insensitive).
- **CLI**: `rig ticket add <id> --project P --title T [--status S] [--owner O] [--evidence E]`,
  `rig ticket list [--project P] [--status S] [--porcelain]`,
  `rig ticket set <id> [--status --owner --evidence --title --project]`, `rig ticket done <id>`,
  `rig ticket rm <id>`.
- **Vista viva**: `rig board [--watch] [--porcelain] [--project P] [--status S] [--interval SEG]`.
  Render agrupado por proyecto y ordenado por estado (`in-progress` -> `blocked` -> `pending`
  -> `done`); `--porcelain` = JSON array (tool-friendly); `--watch` refresca cada `--interval`
  seg (default 1.5s) con ANSI limpio (Ctrl-C sale y restaura el cursor). Dejar abierta en una
  terminal/pane es el uso previsto.
- **Regla**: al abrir/cerrar/actualizar un ticket, reflejarlo en el store con `rig ticket`
  (no editar el JSON a mano). Al cerrar una unidad de trabajo, marcar el ticket `done` con su
  `--evidence` (ruta/test/commit).
- **Abrir el board en herdr** (opcional; lo corre el usuario, ningun agente maneja herdr desde
  afuera): `p=$(herdr pane split --current --direction down --ratio 0.35); herdr pane run "$p" rig board --watch`.
- Dueño: `supervisor` (store/doctrina) + `dotfiles` (script en `~/dotfiles/`).
  Verificacion: `verify run rig` (agrega `jq`, `tickets-store`, `tickets-shape`,
  `tickets-status`, `tickets-unique`, `board-porcelain`, `board-render`) y `rig --selftest`
  (cubre el store con `RIG_TICKETS_FILE` temporal) en **PASS**.

### Doctrina sillas-first: main libre, el trabajo largo corre en sillas

Los `task` in-process de opencode no tienen tty (invisibles en `rig seats`/herdr), **bloquean a
`main`** hasta terminar, **mueren** al reiniciar opencode y un mensaje del usuario los aborta. Por
eso el trabajo **no** corre in-process en `main`, y **esta prohibido delegar con la tool `task`**:

- **main es el punto de entrada y se mantiene libre**: no implementa ni ejecuta trabajo; spawnea
  sillas y sigue disponible para el usuario. Endurecido: `main.md` lleva `permission.task: deny`
  (no puede ni llamar `task`) y `permission.edit/write: deny` (no implementa a mano).
- **Toda delegacion es visible**: una **silla tmux** (`rig spawn`, `rig work new <ticket> --spawn`)
  o un **pane/workspace de herdr**, para que el usuario la vea e interrumpa. Nunca un subagente
  in-process.
- El trabajo largo corre en una **silla tmux**: `rig work new <ticket> --spawn` (worktree + branch
  `ticket/<id>` + silla `work-<id>`), y se le habla con `rig send <silla> "..."`. **Un escritor por
  arbol** (ver el invariante de worktree).
- **Herramientas visibles por defecto**: al spawnear, `rig` arma el **space herdr de la cosa**
  (`--no-herdr` para omitir, `RIG_HERDR=0`) y la **ventana espejo** en una sesion tmux de agentes
  (`--no-mirror`).
- **ESPACIO POR COSA NUEVA (REGLA)**: cada unidad de trabajo nueva abre su **PROPIO space herdr**,
  nombrado por esa cosa: para un ticket el label es `#<num> <titulo>` (o `<id> <titulo>` si aun no
  tiene `num`); para un pedido suelto (`rig spawn` sin ticket) el label es el nombre de la silla.
  Dentro del space, **cada agente es su propia ventana** (tab): al spawnear un 2do agente de la misma
  cosa NO se crea space nuevo, se suma su ventana al space existente (si ya existe una ventana con
  ese label se hace `pane split`). Es **idempotente** (matchea por el id/num de la cosa: label exacto
  o `key + " "`) y **nunca toca spaces ni sillas previos**. `rig spawn` acepta `--ticket <ID>` para
  fijarlo explicito; `rig work new ... --spawn` lo deriva del ticket. `--no-focus` / `RIG_FOCUS=0`
  evitan enfocar. Este modelo **reemplaza** el viejo (workspace = proyecto git, tab = ticket).
- **Estado real del agente en herdr (panel de trazabilidad)**: la silla sigue siendo **una sola
  sesion tmux con UN proceso opencode** (nada de duplicar). Al spawnear, `rig` crea primero el
  tab/pane herdr y arranca la sesion tmux con `-e HERDR_ENV=1 -e HERDR_PANE_ID=<pane> -e
  HERDR_SOCKET_PATH=<sock> -e HERDR_WORKSPACE_ID=<ws> -e HERDR_TAB_ID=<tab>`; con eso el plugin
  `herdr-agent-state.js` reporta `working | idle | blocked` (permiso pendiente = `blocked`). El
  panel de agentes de herdr se puebla solo; el pane herdr solo hace `tmux attach` al mismo
  proceso. Para sillas viejas (spawneadas sin env) o tras recrear panes: `rig herdr sync`
  (registra workspace/tab/pane + titulo `agente · silla`, y reporta estado **derivado** del
  contenido del pane, source `rig:derive`); `rig herdr sync --watch` mantiene el estado al dia.
  Nunca reportar dos fuentes sobre el mismo pane (herdr hace last-write-wins): si el seat tiene
  `HERDR_PANE_ID` en su env, manda el plugin.
- **Limites de herdr 0.8.2** (documentados, no bugs nuestros): no hay clave de config para
  badge/color **por space** en el sidebar (`herdr api schema` solo expone `agent_status` y el
  evento `pane_agent_status_changed`); `report-metadata --title` no cambia `terminal_title`
  (usar `pane rename` para el label). Anidar herdr requiere `[experimental] allow_nested=true`
  en `~/.config/herdr/config.toml` + `herdr config check` + `herdr server reload-config`.
  Actualizar a 0.9.x solo con confirmacion del usuario (hay sillas adjuntas).
- **Modelo explicito siempre**: toda silla arranca con `--model` (default
  `opencode/mimo-v2.6-flash-free`, el nivel barato de la politica de modelos; override
  `RIG_SEAT_MODEL`) para no heredar el ultimo modelo y caer en un provider sin auth. Subir a
  `normal`/`fuerte` es explicito por senal (ver la politica de modelos).
- **Ciclo de vida**: al cerrar el ticket (`rig work finish` / `rig ticket done`) se libera la RAM:
  se matan **TODAS las sillas de su space** (todos sus panes/agentes) y se cierra **el space** (solo
  si el space es de ese ticket: su label matchea el id/num de la cosa), mas sus ventanas espejo
  (`--keep-open` / `--no-close-seat` lo evitan). Nunca mata `main`, sillas sin ticket ni **spaces
  ajenos** (un space legacy de proyecto cae al fallback: cierra solo su ventana/pane); ante duda,
  deja el ticket `blocked` en vez de matar. `rig herdr sync` NO renombra las tabs ya existentes (una
  silla con `HERDR_TAB_ID` en su env solo retitula su propio pane), para no romper las tabs legacy
  con formato viejo.
- Se lee el avance con `rig read <silla>` y, para un vistazo completo, con `rig scan`: ticket/
  proyecto/agente, ruta del worktree, **archivos modificados** (`git status` + `git diff --numstat`,
  incluye untracked), **ultima actividad** (mtime mas reciente), las ultimas ~40 lineas del pane y
  **tokens/costo/tiempo** del ticket (`--porcelain` = JSON).
- Dueño: `supervisor` (doctrina) + `dotfiles` (script). Verificacion: `verify run rig`
  (`scan-cli`, `scan-porcelain`, `scan-empty`, `scan-empty-render`, `seat-model`, `seat-model-env`,
  `rig-tracked`, `herdr-hooks`, `lifecycle-cli`, `tabs-policy`) y anti-rot `verify run agents`
  (checks `sillas-policy`, `main-pure`); `rig --selftest` cubre `scan`/herdr/lifecycle con un
  worktree temporal.

### Invariante: rig SIEMPRE trackeado en git

`linux/bin/rig` es el corazon operativo de la doctrina sillas-first y **debe vivir en el repo**
(`~/dotfiles/linux/bin/rig`, symlink `~/.local/bin/rig`), nunca solo en el arbol de trabajo sin
commitear. Motivo (caso real): durante meses `rig` estuvo **sin trackear** mientras sus features se
apilaban en worktrees/branches paralelos, y eso hizo imposible reconciliar la herramienta. Por eso:
cualquier cambio de `rig` se commitea en la base (o en su worktree `ticket/<id>` que luego integra
`RIG-RECONCILE`); jamas se deja el archivo vivo fuera de git. Check: `verify run rig` → `rig-tracked`
(falla si `git ls-files --error-unmatch linux/bin/rig` no lo encuentra).

### Reconciliacion de ramas paralelas (un solo integrador)

Cuando varias ramas/PRs nacen de la misma base y ninguna contiene a las otras, la integracion se
hace **serial y con verifiacion entre cada paso**, nunca a ciegas:

1. **Un solo integrador**: un ticket dedicado (p.ej. `RIG-RECONCILE`) es el **unico autorizado** a
   mergear en la base; el resto de las sillas siguen en su worktree y no tocan `main`.
2. **Inventario antes de mergear**: por cada rama, `git diff --stat base..rama` y una **matriz de
   features** (grep de marcadores en los archivos que ambas tocan) para saber quien aporta que y
   quien es superset de quien. Nunca mergear sin saber que features pueden perderse.
3. **Checkpoint primero**: commitear/usar un commit de base conocido; si algo se rompe,
   `git reset --hard <checkpoint>` vuelve atras.
4. **Orden de menor a mayor**: primero las ramas que solo agregan, al final la mas grande/conflictiva.
5. **Merge preservando ambos lados**: en `add/add` de un script se toma el superset verificado; si
   los dos divergen, se hace **union 3-way** (`git merge-file`) conservando las features de ambos
   (renombrando colisiones de funciones). En verificadores/registries se **une** (no se elige).
6. **Verificacion entre cada merge**: `verify run rig` + `rig --selftest` + `verify run agents`; si
   rompe, **PARAR** y reportar (no seguir apilando merges sobre algo roto).

Caso real: `RIG-RECONCILE` integro 5 ramas (`herdr-tabs-tickets`, `areas-tickets`, `style-fix`,
`hypr-herdr-hotkey`, `trace-visibility`) sobre la base `df45bcd`; `rig` quedo como la union de
`areas` (areas/numeracion/titulos) y `trace` (eventos/central/log/say/agents/queue).

## Invariante: ningun pedido de trabajo queda sin lanzar

REGLA DURA: cuando el usuario pide trabajo (una feature, un fix, una tarea de sistema que se
va a ejecutar), `main` **abre el ticket y la silla en el momento** (`rig work new <id> --cwd
<repo> --spawn` + `rig send`, o `rig ticket add <id> ...` + `rig spawn`), o cambia al agente
owner. **Nunca** deja el pedido en `"¿lo lanzo?"`: o lo lanza, o lo cierra con estado explicito
(`pending`/`blocked`) y motivo. Un pedido sin desarrollar es un fallo de flujo.

- **Pregunta solo si hay bloqueo real**: accion riesgosa/irreversible, falta un dato que cambia
  el resultado, o dos caminos validos excluyentes. La duda de "lanzar o no" NO es bloqueo: se
  lanza (visible e interrumpible) y el usuario redirige.
- **Estado honesto**: `in-progress` significa "hay una silla viva trabajando el ticket". Un
  ticket in-progress sin silla viva (ni worktree vivo) es **stale**: se relanza
  (`rig work new <id> --cwd <repo> --spawn`) o se marca `pending`/`blocked`, jamas se deja
  `in-progress` huerfano.
- **Ciclo completo, nunca entregable parcial**: si el pedido admite diagnostico + fix, el
  encargo es el ciclo entero (diagnostico -> fix -> `verify` -> evidencia -> ticket
  `done`/`blocked`). Prohibido cerrar una delegacion con un entregable parcial (p.ej. solo el
  diagnostico) dejando el ticket `in-progress`.
- **La silla cierra su ticket**: al terminar su unidad, la silla DEBE reflejar el resultado en
  el store en el momento (`rig ticket done <id> --evidence ...` o `rig ticket set <id> --status
  blocked --evidence ...`). Silla que termino y quedo idle con el ticket `in-progress` = fallo
  de flujo.
- **main cierra los bucles**: tras CADA interaccion del usuario y antes de cerrar cualquier
  unidad, `main` corre `rig scan` / `rig board`, detecta los tickets `in-progress` con silla sin
  actividad reciente (`stale`, ver check `tickets-idle`) y los cierra: relanza
  (`rig work new <id> --cwd <repo> --spawn`) o marca `pending`/`blocked`. `main` nunca asume que
  la silla aviso.
- **Entrega confirmada (REGLA DURA)**: ninguna silla se considera lanzada hasta que su encargo esta confirmado. Lanzar trabajo es UNA operacion determinista: `rig launch
  <ticket-id> --cwd <repo> --brief <archivo>` (o `rig spawn ... --brief <archivo>` / `rig work
  new ... --spawn --brief <archivo>`) crea el ticket (si no existe) + su worktree + su silla y
  entrega el encargo: espera a que la interfaz este realmente lista (sin sleeps fijos), lo pega
  y CONFIRMA que llego (el texto aparece en el panel o el consumo de contexto de la silla dejo
  de ser cero). Si no confirma tras los reintentos, NO reporta exito: emite el evento
  `launch-failed`, deja el ticket en `blocked` con el motivo y sale con codigo distinto de cero.
  Una silla viva con el panel vacio y consumo cero es "encargo no entregado" (el check
  `tickets-idle` y `rig scan` lo marcan `undelivered`), nunca "trabajando".
- Dueño: `supervisor`. Verificacion: `verify run agents` (checks `launch-policy`,
  `tickets-live`) + `verify run rig` (checks `tickets-idle` y `launch-failed-blocked`, senal de
  sillas in-progress idle o con encargo no entregado).

## Invariante: un problema = un ticket (el seguimiento vive en la misma unidad)

REGLA DURA (pedido del usuario): un problema reportado es **UN** ticket, y todo el trabajo que lo
resuelve —aunque toque otro dominio o repo— vive en **ese** ticket. Prohibido abrir un ticket
nuevo para el seguimiento, y prohibido re-diagnosticar de cero lo que el agente que atiende ya
sabe. Caso real: el arreglo del Gateway de OpenClaw (#187) se partio en un segundo ticket (#188)
para un cambio de 2 lineas; fueron dos tickets, dos sillas y dos diagnosticos para un solo
problema, y aun asi el resultado no quedo vivo hasta integrar.

- **Cerrar el ciclo entero en la misma unidad**: diagnostico -> fix -> integracion -> verificacion
  en vivo -> evidencia, todo bajo el mismo ticket. Un ticket `done` con el resultado a medias
  (p.ej. el fix en un branch sin integrar a la rama que el usuario ve) **no** es cierre.
- **Umbral de autofix vs silla del owner**: si el cambio es chico (1-2 archivos), de bajo riesgo,
  ya diagnosticado y **no hay otro escritor en ese arbol**, el agente que atiende lo hace y lo
  verifica directo (tier `micro`/`medio`, ver E3). La silla del owner del dominio se reserva para
  multi-archivo, riesgo alto (foco, input, shell/QML, migraciones) o arbol con otro escritor (ver
  el invariante de worktree). **No** se abre una silla nueva para lo que el agente actual resuelve.
- **Cross-dominio sin ticket nuevo**: si hace falta tocar otro repo (p.ej. el gateway y la app), se
  hace en el **mismo** ticket, en el worktree de ese repo; el owner del dominio aporta su
  verificacion. Si el agente que atiende no puede editar ese repo, delega en una silla del owner
  pero el ticket original sigue siendo el unico ticket del problema.
- **`main` no edita** (`permission.edit/write: deny`): sigue delegando en silla, pero **mantiene el
  mismo ticket**; no abre uno nuevo para continuar el mismo problema.
- **Medir la via**: antes de spawnear, estimar el costo (tokens/costo) de la via elegida y preferir
  la mas barata que cubra el riesgo; registrar la via usada en el ticket (`rig ticket metrics`). Una
  silla nueva para lo trivial es costo sin retorno.
- Dueño: `supervisor`. Verificacion: `verify run agents` (check `flow-policy`, falla si esta regla
  desaparece del `AGENTS.md`).

## Invariante: developing es la unica fuente de verdad (el usuario juzga lo que ve)

REGLA DURA, pedido directo del usuario: en cualquier proyecto que tenga una rama `developing`,
esa rama es la unica fuente de verdad y el arbol que el usuario ve. Un cambio **no existe**
hasta que esta integrado y servido en developing; el usuario no lee las ramas `ticket/*` ni
`main`, juzga por lo que la app servida le muestra. Dar por terminado un cambio que solo vive en
una rama de ticket es el peor fallo de flujo: el usuario ve la app vieja, la cree rota y la
reporta de nuevo.

- **Definicion de terminado (todo o nada)**: commit en la rama del ticket -> merge a
  `developing` -> app de `developing` reconstruida/servida mostrando el cambio -> `verify` en
  verde **sobre `developing`**. Sin integrar y servir en developing, el ticket no se cierra ni se
  reporta "listo".
- **Prohibido reportar "arreglado" con el cambio solo en la rama `ticket/*` o en `main`**.
  Caso real: el ancho de los mensajes de los hilos se arreglo en `ticket/plataforma-hilos-ancho`,
  pero `developing` (lo que el usuario ve) seguia ancho; el usuario lo reporto otra vez.
- **Verificacion determinista antes de cerrar** (desde el worktree de `developing`):
  `git branch --contains <commit>` debe listar `developing`, o el marcador del cambio debe
  aparecer en el archivo ya presente en `developing`. Si el cambio no esta ahi, el ticket queda
  `in-progress`/`blocked`, nunca `done`.
- **Si el proyecto no tiene `developing`**: aplica la rama/arbol que se sirve en vivo; preguntar
  antes de asumir cual es.
- Dueño: `supervisor`. Verificacion: `verify run agents` (check `developing-policy`, falla si esta
  regla desaparece del `AGENTS.md`).

## Invariante: ciclo de vida de sillas (no cerrar ajenos; el space lo cierra el usuario)

REGLA DURA, pedido directo del usuario: un agente **no cierra sillas, espacios ni tickets ajenos**.
Un agente solo toca SU unidad; al terminarla, la silla marca su ticket `done`/`blocked`
y **deja la silla y el espacio vivos** para que el usuario los cierre. Cerrar o matar el trabajo
de otro agente rompe la trazabilidad y es un fallo grave (caso real: una silla cerro el ticket
`HERMES-PILOT`, autorizado por el usuario, y mato su silla).

- **Enforcement en `rig`**: `rig ticket set/done/rm` y `rig work finish/rm` se niegan si el actor
  es una silla distinta de la dueña del ticket (`seat_can_touch_ticket` / `seat_owns_ticket`; la
  dueña es `work-<id>`, `<id>` normalizado, `ticket.seat`, o la silla cuyo cwd es el worktree).
  Override explicito y puntual: `--force` (o `RIG_FORCE_CROSS=1`). `close_seat_for_ticket` no
  cierra una silla ajena. `main` (o el usuario, fuera de tmux) puede operar cualquier ticket.
- **Cierre del ticket por cierre del space (senal de resolucion)**: cada unidad abre su propio
  space herdr y el ticket guarda su id (`space`). Cuando el usuario da la cosa por resuelta,
  **el cierre del espacio por el usuario** es la senal: `rig spaces reconcile` (o `rig spaces
  --watch`) detecta los spaces que ya no existen y **marca ese ticket done** con evidencia
  "space cerrado por el usuario". Ninguna silla debe cerrar el space para "terminar".
- **Estado fiel (nada en working si murio)**: una silla **no puede quedar en working** si su
  agente murio o nunca arranco. `rig agents` valida que la sesion tmux exista y que el foreground
  sea un agente (no un shell): si no, reporta estado `dead` (fuente `probe`), y `rig herdr sync`
  no reporta estado para una silla muerta. Un ticket `in-progress` sin silla viva es **stale**:
  `main` cierra el bucle (relanza o marca `pending`/`blocked`), nunca se deja huerfano.
- **Cierre explicito**: `rig work finish --close-seat` / `rig ticket done <id> --close-seat`
  cierran silla+space solo con intencion explicita; el default **deja todo vivo**.
- Dueño: `supervisor`. Verificacion: dominio `agents` (check `lifecycle-policy`) + dominio `rig`
  (checks `no-close-policy`, `state-fidelity`, `spaces-cli`, `space-done-on-close`).

## Invariante: cambios paralelos con git worktree por ticket

Regla dura: **un escritor por arbol**. Dos agentes jamas escriben el mismo working tree a la
vez. Para paralelizar en un mismo repo, cada ticket corre en su propio **git worktree** +
**branch** (`ticket/<id>`), nunca en el arbol principal. Eso elimina la carrera (p.ej. dos
subagentes tocando `static/` de foldertinder) y deja **trazabilidad** completa
(ticket -> branch -> worktree -> commits -> evidencia -> verify).

- **Herramienta**: `rig work` (fuente `~/dotfiles/linux/bin/rig`; owner `supervisor`+`dotfiles`).
  - `rig work new <id> [--agent A] [--cwd DIR] [--base REF] [--spawn] [--attach]`: crea el
    worktree en `<parent-del-repo>/.rig-worktrees/<repo>/<id>` y el branch `ticket/<id>`;
    registra `repo/branch/worktree/base` en el ticket y lo pone `in-progress`. `--spawn` abre
    una silla (`rig spawn work-<id>`) en el worktree. Ubicacion: override `RIG_WORKTREE_DIR`.
  - `rig work list [--porcelain]`: tickets con worktree (branch, commits, si el arbol vive).
  - `rig work finish <id> [--no-verify] [--no-commit] [--keep-open] [--force]`: corre
    `verify auto` sobre lo cambiado, commitea el branch y cierra el ticket (`done`) con
    evidencia `branch:<b> commit:<sha> verify:<PASS|SKIP|FAIL>`. **No mergea.**
  - `rig work rm <id> [--delete-branch] [--force]`: elimina el worktree (conserva el branch
    salvo `--delete-branch`).
- **Tablero**: `rig board` muestra `BRANCH` y `COMMITS` por ticket (con la ruta del worktree
  debajo de la fila); `rig work list` agrega el estado real del arbol.
- **Merge explicito y serial**: integrar es el unico paso que toca la base (compartida), asi
  que se hace a mano y de a uno: `git -C <repo> merge --no-ff ticket/<id>`. Un conflicto de
  merge es una senal de coordinacion real, no de paralelismo roto.
- **Cuando NO hace falta worktree**: un solo agente en el repo (o cambios triviales) puede
  commitear directo en la base. Si hay **2+ escritores** en el repo, el worktree es
  obligatorio. El reparto por archivos disjuntos es un complemento (menos choques), no una
  garantia: las capas compartidas (`static/css/`, `app/globals.css`, entrypoints) se tocan
  igual, y mas granularidad reduce pero nunca elimina el choque.
- **Casos reales**:
  - `foldertinder`: el servicio (systemd, puerto 8777) sirve **en vivo** el arbol principal.
    Un worktree es un **staging**: nada se ve en 8777 hasta el merge; un cambio `.py` pide
    `systemctl --user restart foldertinder.service` despues del merge, no antes.
  - `agentes-platform` (Next.js): cada worktree necesita su propio `node_modules`/`.next`
    (deps no compartidas); el worktree aisla pero no es gratis.
- **Por que worktree y no branch-only o reparto por archivos**: un branch sin worktree
  comparte un solo working tree -> sigue siendo serial; el reparto por archivos no garantiza
  nada ante capas compartidas. El worktree es la unica opcion que da aislamiento real (un
  indice/arbol por ticket) y usa git estandar.
- Dueño: `supervisor` (doctrina) + `dotfiles` (script). Verificacion: `verify run rig`
  (checks `git`, `work-cli`, `tickets-work-shape`, `worktree-link` + selftest que crea
  worktree+branch, commitea via `work finish` y limpia via `work rm`) y anti-rot
  `verify run agents` (check `worktree-policy`). Config nueva -> reinicia opencode.

## Invariante: linea `developing` en agentes-platform (forks y commits ahi)

En la app `agentes-platform` (el cockpit de agentes y tickets), `main` es la **linea
estable** y `developing` es la **linea de integracion**. Todo agente nuevo que trabaje en
esa app **forkea de `developing`** (no de `main`), avanza en su propia rama/version y
**commitea ahi**, para no pisarse entre si; `main` solo recibe lo ya integrado y estable.

- **Worktree**: los tickets de `agentes-platform` se abren con `rig work new <id> --cwd
  <repo agentes-platform> --base developing`; el `--base` es `developing`, nunca `main` ni
  el `HEAD` de `main`.
- **Integracion**: los branches de esos tickets se integran a `developing` (serial, con
  verificacion entre cada paso); `developing` -> `main` solo cuando la linea esta estable.
- **Alcance**: aplica solo a `agentes-platform`; el resto de los repos siguen la doctrina
  general de worktree por ticket sobre su rama por defecto.
- **Nota en el repo**: la app lleva su propia nota de esta regla en su `AGENTS.md`; su owner
  es `app-architect` (ticket #178) y ese repo no se edita desde aca.
- Dueño: `supervisor` (doctrina) + `app-architect` (owner de la app). Verificacion:
  `verify run rig` (check `developing-policy`, falla si esta regla desaparece de este
  `AGENTS.md`). Config nueva -> reinicia opencode.

## Metricas por ticket (tokens/costo/tiempo) — trazabilidad de costo

Cada ticket puede llevar el rastro de **costo real**: tokens, dinero y tiempo. Fuente de
verdad: `~/.local/share/opencode/opencode.db` (sqlite, por `session.id`); opencode guarda por
sesion `cost`, `tokens_input/output/reasoning/cache_read/cache_write` y
`time_created/time_updated`. Los `task` subagentes son sesiones con `parent_id` = la sesion que
los lanzo, asi que el costo de un ticket es su sesion + descendientes.

- **Mapeo ticket -> sesion(es)**: al lanzar el trabajo de un ticket, registra el id con
  `rig ticket set <id> --session ses_xxx` (append, dedup), `rig ticket add ... --session`, o
  `rig work new <id> --session ses_xxx`. Ademas `rig` auto-vincula las sesiones cuyo
  `directory` == worktree del ticket (una silla `--spawn` queda ligada sola).
- **Lectura (solo-lectura, sin deps nuevas)**: `sqlite3 -readonly` (CLI) + `jq`; override del
  DB con `RIG_DB`; desactivar con `RIG_METRICS=0`.
- **CLI**:
  - `rig board` agrega la columna `METRICS` por ticket: `<total> $<costo> <duracion>` (total =
    input+output+reasoning; cache aparte). `--no-metrics` para omitir.
  - `rig board --porcelain` agrega `metrics{tokens{...},cost,time{duration_ms}}` por ticket
    (API lista para el cockpit).
  - `rig ticket metrics [<id>...] [--porcelain]`: desglose in/out/reasoning/cache.read/
    cache.write/total, costo, creado/actualizado/duracion y nº de sesiones.
- **Cockpit (`agentes-platform`)**: consumir `rig board --porcelain` / `rig ticket metrics
  --porcelain` (no re-implementar la lectura del DB). Ese repo NO se edita desde aca.
- Dueño: `supervisor` (doctrina) + `dotfiles`. Verificacion: `verify run rig` (checks
  `sqlite3`, `metrics-cli`, `db-schema`, `tickets-sessions-shape` + selftest con sqlite
  temporal) y anti-rot `verify run agents` (check `metrics-policy`).

## Invariante: sesiones tmux idle se auto-reapan (2h)

Ninguna sesion tmux sin adjuntar vive mas de 2h de inactividad. Unidad
`~/.config/systemd/user/tmux-reap.timer` (cada 10min, +5min tras boot) ejecuta
`~/.local/bin/tmux-reap.sh` (fuente versionada: `~/dotfiles/linux/bin/tmux-reap.sh`).

- Politica: `TMUX_REAP_HOURS` (default 2) y `TMUX_REAP_FILTER` (regex de nombres,
  solo para tests/uso puntual). Sesiones adjuntas jamas se tocan.
- Dueño: agente `dotfiles`. Verificacion: `verify auto tmux-reap.sh tmux-reap.service
  tmux-reap.timer` (dominio `systemd`: shellcheck + selftest + `systemd-analyze` +
  timer active). El selftest crea y mata su propia sesion `_reap_selftest`; filtrar
  por nombre es obligatorio, jamas correr con HOURS=0 sin filtro.
- Sesion de opencode reapeada queda en storage y se puede resumir; matar sesiones
  adjuntas o con trabajo activo sigue prohibido sin confirmar.

## Regla meta: todo cambio de sistema deja owner + regla + verificacion

Una tarea de sistema que se va a repetir **no se resuelve ad-hoc**. Antes de cerrarla, deja
el sistema listo para el proximo agente, en este orden:

1. **Owner**: crea/extiende el agente dueño del dominio (`~/.config/opencode/agents/<owner>.md`)
   que cubra el alcance, las skills a cargar y el flujo obligatorio.
2. **Verificacion determinista**: monta o extiende un verifier/lint/script
   (`verify scaffold <dominio> "<glob>"`, `~/.local/bin/`) que detecte la regresion de forma
   automatica. Un cambio sin check es una bomba de tiempo.
3. **Regla**: documenta el invariante en este `AGENTS.md` (o en la skill del dominio).
4. **Estilo**: solo despues, convenciones/nombres.

`supervisor` audita que cada dominio tenga **owner + regla + verificacion** y reporta los
huecos; ademas mide fallbacks, loops y uso de contexto. Config nueva (agentes, plugins,
skills, reglas) **NO se hot-reloadea**: reinicia opencode para que aplique.

## Invariante: todos los agentes son accesibles por todos los agentes

El `task` tool expone **todos** los agentes con `mode != primary` (salvo `permission.task`
en deny). El registry de agentes se carga **una sola vez al arrancar opencode** y NO se
hot-reloadea: un agente creado o editado despues del arranque queda invisible para la
sesion en curso, y el hilo principal acaba reimplementando a mano lo que el agente experto
ya sabe ("reinventar la rueda"). Caso real: `browser-pilot` existia pero un server viejo
no lo veia y no se pudo delegar.

- **Regla**: tras crear/editar cualquier `~/.config/opencode/agents/*.md`, **reinicia
  opencode**. Ninguna tarea de agente se cierra sin `verify run agents` en PASS.
- **Verificacion**: dominio `agents` (verifier `agents.sh`). Checks: `spec` (frontmatter
  con `name` y `description` que incluya `Triggers:`; `mode` valido si existe), `desc-budget`
  (suma de descripciones <= 9000 chars, evita saturar el contexto del `task` tool) y
  `registry-fresh` (falla si el agente mas nuevo es mas reciente que el server opencode
  ancestro -> pide reiniciar). Corre en `verify auto` sobre cualquier `agents/*.md`.
- **Contexto**: el `task` tool inlinea TODAS las descripciones (~7000 chars hoy). Al crear
  un agente, descripcion concisa; el presupuesto total lo vigila `desc-budget`.
- Dueño: `supervisor` (meta: agentes/eficiencia) + `dotfiles` (verifier). Selftest:
  `verify selftest`.

## Browser agent real (browser-pilot): uso + memoria

Control del navegador REAL (Brave del usuario) via `browser-control` (relay local + extension MV3
cargada en el Brave abierto). Owner: agente `browser-pilot`. Skill:
`~/.config/opencode/skills/browser-pilot/` (symlink a `~/dotfiles/linux/config/opencode/skills/browser-pilot/`).

- **Memoria (archivos, sobrevive sesiones)**: `selectors.json` (selectores por sitio),
  `playbooks/<site>.md` (gotchas/recetas), `runs.jsonl` (log append-only de cada tarea real).
- **Runner rapido**: `node lib/pilot.mjs <tarea> --session <id>` (o env `PILOT_SESSION`);
  `--stats` resume `runs.jsonl`. Tareas: `playLatestYouTube`, `searchPlayYouTube`,
  `latestPostsX`, `wikiSummary`.
- **Regla**: leer el playbook del sitio ANTES; usar waits por condicion (`waitForFunction`),
  NUNCA sleeps fijos; el codigo de `execute` corre en Node/Playwright -> DOM via `page.evaluate`;
  devolver `JSON.stringify`. Si un selector rota (p.ej. layout nuevo de YouTube), corregir
  `selectors.json` + playbook en el momento.
- **Limites**: prohibido loguear/automatizar Meta/WhatsApp/Clerk sin human-in-the-loop; sin
  acciones irreversibles; sin exfiltrar cookies.
- **Verificacion**: `verify run browser` (checks sin red: schema selectors, playbooks, runs.jsonl,
  sintaxis lib) y `verify auto` sobre la skill.

## Estandares de codigo (obligatorio)

Todo codigo que escribas o modifiques debe ser, sin excepcion:

- **Autoexplicativo**: nombres claros, estructura legible, sin comentarios que repitan lo
  obvio. El codigo se entiende solo; los comentarios explican el *por que*, no el *que*.
- **Tipos fuertes**: tipar todo (params, retornos, estructuras). Prohibido `any`/tipos
  debiles salvo justificacion explicita. En lenguajes sin tipos, usar el equivalente
  (validacion, dataclasses, schemas).
- **Tests**: toda logica no trivial lleva tests que la cubran. No cerrar una tarea sin
  correr los tests relevantes.
- **Static analysis**: pasar linter + type checker + formatter del proyecto antes de
  terminar. Corregir TODO error/warning propio.

Si el proyecto no tiene todavia tests ni static analysis configurados, proponer y montar el
minimo (test runner, linter, type checker) antes de dar por cerrada la tarea.

## Codigo sin comentarios (REGLA DURA)

Prohibido escribir comentarios en el codigo, en cualquier lenguaje (`//`, `#`, `/* */`, `--`,
`<!-- -->`, etc.). Un comentario es un **defecto**, no una ayuda.

Motivo: esta codebase es **agent-first, no human-first**. Un agente entiende el codigo por sus
nombres, tipos y estructura. Los comentarios se desincronizan, agregan ruido y tokens, y suelen
tapar codigo poco claro.

- El codigo se explica solo: nombres claros, tipos fuertes, funciones pequenas, contratos obvios.
- El "por que" de una decision va en `AGENTS.md`, una skill, o el mensaje de commit. Nunca en el codigo.
- Excepciones (solo cuando una herramienta las exige, no como prosa): shebang, directivas de
  compilador/preprocesador, y anotaciones que el static analysis lee (`# type:`, `# noqa`,
  `// @ts-`, `//go:build`, etc.).
- Enforcement: el plugin `no-comments.js` **bloquea** la edicion si detecta un comentario nuevo.
  Override explicito y puntual del usuario: `OPENCODE_ALLOW_COMMENTS=1`.

## Arquitectura de apps: agent-friendly (obligatorio)

Toda app que se construya en esta maquina sale **agent-friendly** (contrato **AFA v1**): 1
responsabilidad por archivo, estructura feature-first, tipos en los boundaries, logica en
funciones puras, linter + typecheck + tests. Regla aprobada formalmente por el usuario. El
objetivo es escribir **menos y mas claro**, no mas LOC.

- **Contrato (fijo, no negociable)**: archivo fuente (`js/ts/tsx/jsx/css/scss/py/rs/go/html/...`)
  **> 400 lineas = HARD FAIL**, WARN > 300. **Monolito prohibido**: repo cuya unica app sea
  `index.html` + `app.js`/`main.js` + `style.css`/`app.css` en la raiz sumando **> 600 lineas**.
  Tipos en boundaries (sin `any` sin justificar), tests obligatorios, `AGENTS.md` por proyecto.
- **Estructura**: `src/features/<f>/{ui,model,api,types}`, `src/components/`, `src/lib/`,
  `src/types/`, `src/hooks/`, `tests/`. Una feature no importa el `model/` ni la `ui/` de otra.
- **Scaffold por defecto**: `new-app <nombre> <tipo>` (nunca arrancar un repo a mano).
- **Linter on-edit**: `app-arch-lint` corre automatico en cada edit (plugin) y marca
  `file-too-long`, `root-monolith`, `bad-structure`, boundaries rotos. Corregir TODO ERROR.
- **Owner**: agente `app-architect` (dueño exclusivo de como se estructura/scaffoldea una app).
  NO implementa UI/UX (eso es `ui-ux`) ni automatiza navegador (eso es `browser-pilot`).
- **Verificacion determinista**: `verify run app-arch` (estructura, tamanos, boundaries,
  `AGENTS.md` del proyecto, linter/typecheck/tests) en **PASS** para cerrar. El contrato AFA v1
  y los principios portados de pstack viven en la skill `agent-friendly-app`.
- **Deuda conocida** (motivo de la regla): `foldertinder/static` (`app.js` 3548 + `app.css` 3060
  + `index.html` 291), `hypr-remote/public/app.js` 4266.
- Config nueva (agentes, skills, reglas) **no se hot-reloadea**: reinicia opencode.

## Regla: nunca compilar Qt5 desde fuente (AUR con deps retiradas)

`qt5-webengine`, `qt5-webchannel` y `qt5-location` **salieron de los repos
oficiales de Arch**. Un `yay -S` que los declare como dependencia intenta
compilar **qtwebengine desde fuente** (Chromium, ~24000 targets ninja): horas de
build que mueren a mitad. Esa es la causa real de los intentos fallidos de
`stremio-bin`.

Flujo obligatorio antes de instalar un paquete AUR con deps Qt5:

1. `pacman -Si <dep>` sobre cada dependencia. Si alguna no está en repo, **no**
   dejar que yay la compile.
2. Bajar el `.pkg.tar.zst` precompilado de
   `https://mirror.cachyos.org/repo/x86_64/cachyos/` e `sudo pacman -U`.
3. `openssl-1.1` no está en ningún repo ni en CachyOS: AUR con
   `yay -S openssl-1.1 --noconfirm --mflags="--nocheck"` (su `check()` falla
   siempre por `30-test_afalg.t`, no es un bug real).
4. Recién ahi: `yay -S <pkg> --noconfirm`.

Higiene: borrar `~/.cache/yay/qt5-webengine/` si quedo a medias (ocupa GB).
Dueño: agente `dotfiles`. Verificacion: `verify run packages`.

## Toolchain Rust + deps Tauri 2 (host)

Host listo para compilar una app Tauri 2 (Rust). Toolchain via `rustup` del repo
oficial (`extra`), default toolchain `stable`. En Arch los binarios `rustc`/`cargo`/
`rustup` son **shims en `/usr/bin`** (los provee el paquete `rustup`), por eso no
existe `~/.cargo/env`; `~/.cargo/bin` (destino de `cargo install`, p.ej. `cargo-tauri`)
se agrega al PATH de forma idempotente en `~/.bashrc`.

Deps de sistema, solo paquetes de repos oficiales (jamas AUR): `base-devel`,
`webkit2gtk-4.1`, `gtk3`, `librsvg`, `patchelf`, `xdotool`, `openssl`, mas un
appindicator (`libappindicator` o `libayatana-appindicator`). Instalar con
`sudo pacman -S --needed --noconfirm ...` tras verificar con `pacman -Si`.

Regla: **no compilar la app** como paso de verificacion (el dominio `code` corre
`cargo clippy`/`cargo test` y compila). Por eso el dominio `tauri` (priority 12)
gana sobre `code` (10) para `src-tauri/Cargo.toml`.
Dueño: agente `dotfiles`. Verificacion: `verify run tauri` (checks `toolchain:rustc`,
`toolchain:cargo`, `toolchain:rustup`, `default-toolchain`, `deps-installed`,
`appindicator`, `pkgconfig:webkit2gtk-4.1`, `cargo-bin-path`).

## Braindump / Obsidian (vault `alicia`)

El braindump del usuario vive en `~/alicia` (`Inbox/`, `Proyectos/`, `Areas/`,
`Daily/`, `Archivo/`). El usuario piensa mucho y se dispersa: el objetivo es
capturar rapido sin frenar el trabajo en curso y despues ejecutar/organizar.

- **Captura bajo demanda**: el usuario habla ("apunta esto", "guarda mi idea",
  "anótalo", "deja esto pendiente", "recordame", "braindump", "en alicia") ->
  cargar skill `obsidian` y correr `obsidian-note add ...` en UNA linea de
  comando. Confirmar en UNA linea y **retomar la tarea anterior sin rodeos**.
- El usuario NUNCA da comandos: solo habla. El agente detecta `tipo`
  (idea | tarea | recordatorio | pensamiento) del contenido y limpia muletillas
  de transcripcion de voz sin inventar.
- **Cuando capturar (REGLA)**: solo en dos casos. (1) El usuario lo pide
  explicitamente ("apunta esto", "recordame", "deja esto pendiente"). (2) Hay una
  **idea o pendiente claro** que vale la pena conservar. Fuera de eso, NO captures:
  nada de feedback de estilo, correcciones al agente, charla operativa ni
  conversacion de coordinacion. Antes se auto-capturaba cada pregunta o reflexion;
  eso generaba ruido y el usuario duda de la utilidad de esas notas (ver ticket
  STYLE-FIX). Al capturar, elegir `tipo` y destilar la tesis + lo util, no
  transcribir literal.
- Consulta/organizacion: `obsidian-note list --estado pendiente`, `promote`
  (Inbox -> Proyectos, estado `en-curso`), `done` (estado `hecha`). Dashboard vivo
  del vault: `~/alicia/Tablero.md` (plugin Dataview, corre solo con Obsidian abierto).
  El frontmatter (`tipo`/`estado`/`tags`/`fecha`) alimenta el tablero: no romperlo.
- Dueño: skill `obsidian` (`~/.config/opencode/skills/obsidian/SKILL.md`).
  Script: `~/dotfiles/linux/bin/obsidian-note` (symlink `~/.local/bin/`).
- Verificacion: `verify auto ~/dotfiles/linux/bin/obsidian-note` (dominio
  `obsidian`: shellcheck + selftest + symlink + estructura del vault) y
  `verify selftest` tras tocar el verifier.

## Pipeline AI chats (embeddings + MCP)

Centraliza conversaciones exportadas de chats web con LLMs. Staging
`~/Downloads/AIChats/*.md` (frontmatter `title`/`url`/`source`) -> ingesta
classifica por URL (`chatgpt|claude|gemini|grok|deepseek`, fallback `Varios`) ->
`~/ai-chats/<Plataforma>/` + indice `~/ai-chats/chats.sqlite` (sqlite-vec,
vec0, cosine). Embeddings locales: `intfloat/multilingual-e5-small` (384-dim,
fastembed, prefijos `query: `/`passage: ` aplicados a mano). Dueño: agente
`dotfiles`.

- Paquete: `~/dotfiles/linux/ai-chats/` (install editable en `~/ai-chats/.venv`,
  Python 3.13; mypy strict + ruff + pytest).
- Comandos (symlinks `~/.local/bin/`, fuente `~/dotfiles/linux/bin/`):
  - `ai-chats-ingest` — mueve el staging, clasifica, dedupe por sha256
    (`AI_CHATS_SETTLE_SECS` para tuning; archivos <2s se ignoran).
  - `ai-chats-embed` — embedding incremental (vía sha en `embedded_sha256`),
    `--rebuild` reconstruye el indice.
  - `ai-chats-search "<query>" [-k N]` — busca y formatea hits.
  - `ai-chats-mcp` — servidor MCP stdio (`mcp` 2.x, `MCPServer`, el FastMCP
    moderno) con tool `search_conversations(query, k=5)`.
- Automatización (units en `~/dotfiles/linux/system/systemd-user/`, instaladas
  en `~/.config/systemd/user/` por `setup-omarchy.sh`):
  - `ai-chats-ingest.path` — al caer un archivo en el staging dispara
    `ai-chats-sync.service` (sleep 3s + ingest + embed, ingesta inmediata).
  - `ai-chats-sync.timer` — red de seguridad cada 10min (+2min tras boot).
- Modelo cacheado en `~/.cache/fastembed/` (465MB): `FASTEMBED_CACHE_PATH` se
  fija en `embedder.py` porque el default de fastembed es `/tmp` y se pierde
  en cada reboot.
- MCP en opencode: entrada en `opencode.json`
  `{"ai-chats": {"type": "local", "command": ["ai-chats-mcp"], "enabled": true}}`.
  Sin registrar, `mcp:registered` sale SKIP con el comando exacto.
- Verificacion: `verify run ai-chats` (ruff/mypy/pytest, 4 selftests, symlinks,
  shebang venv, units enabled+active+drift, esquema sqlite+vec0+meta,
  model-cache, MCP). Verifier: `verifiers/ai-chats.sh` (priority 15, gana a
  `code`). Tras tocar units: `verify auto <unit>` (dominio `systemd`).

## Verificacion proporcional al riesgo (E3)

El default de un agente es "maximum-context-first": un edit de 1 linea se convierte en una
auditoria del codebase y gasta 20 min de E2E para un riesgo bajo. Se prohibe. Estima el TIER
**antes** de ejecutar (framework E3: Estimate -> Execute -> Expand), corre el camino minimo de
verificacion y expande UN nivel solo si falla o la confianza cae. La redundancia cuesta mas en
las tareas mas simples.

Tiers (elige **el menor** que cubra el riesgo):

| Tier | Cuando | Verificacion minima (y suficiente) |
|------|--------|------------------------------------|
| `micro` | 1-2 lineas / valor de config, sin foco/input/UI | `hyprctl reload` (o recarga equivalente) + `hyprctl configerrors` + `verify auto <archivo>`. **PROHIBIDO** montar harness E2E. |
| `medio` | logica acotada, 1-5 archivos, sin efectos criticos | `verify run <dominio>` + spot-check del efecto |
| `riesgoso` | foco, input, plugins, shell/QML, systemd, migraciones, multi-maquina, o algo que no se revierte facil | E2E real (nested/dry-run) + casos negativos |

Reglas (duras):

- **Empieza en el tier mas bajo que cubra el riesgo.** Nunca arranques en el mas alto.
- **Expande UN nivel solo si** la verificacion falla o la confianza cae. No antes.
- **Anti-overcheck**: corta en el PRIMER PASS. Prohibido re-verificar un resultado ya verde
  (un re-check es confirmatorio, no correctivo; solo gasta tokens).
- **Stop-and-ask**: antes de montar un harness E2E, o si vas a exceder ~10 min de subagente
  o muchas tool calls, PARA y pregunta al usuario: "¿ligero o a fondo?".
- **Escala por SEÑAL, no por confianza** (el modelo es sobre-optimista): tocar 3+ archivos
  fuera del pedido, repetir tool calls casi identicas (loop) o exceder el presupuesto ->
  parar y reportar/preguntar.
- **Cierre**: todo reporte final cita el tier elegido y el comando EXACTO de verificacion usado.

Dueño: `supervisor`. Verificacion: dominio `agents` (`policy-present`, `agents-declare-tier`).

## Estilo de respuesta: caveman apagado por defecto (owner supervisor)

El estilo de respuesta es una regla dura (ver la primera seccion de este archivo). El
plugin caveman (`~/.config/opencode/plugins/caveman/`) queda **apagado por defecto** y solo
se activa si el usuario lo pide (`/caveman` o "stop caveman" para salir).

- **Capas apagadas**: (1) `~/.config/caveman/config.json` con `{"defaultMode":"off"}` (fuente
  versionada: `linux/config/caveman/config.json`); (2) el flag
  `~/.config/opencode/.caveman-active` eliminado y en `.gitignore`; (3) sin bloque
  caveman en este `AGENTS.md`. Un flag con valor `off` NO sirve: el plugin lo trata como
  activo y reinyecta; hay que borrar el archivo.
- **Por que**: caveman fuerza estilo telegrafico y sin articulos, y el modelo ademas caia en
  voseo argentino. El usuario pidio espanol neutro y tecnico simple. La correccion va en la
  config de los agentes, no en una nota de Obsidian.
- **Verificacion**: dominio `agents`, check `style-policy` (falla si falta la regla de estilo
  en `AGENTS.md` o `main.md`, o si caveman queda activo por defecto). Ademas `verify auto` sobre
  `linux/config/caveman/config.json`.
- Dueño: `supervisor`. Config nueva **no se hot-reloadea**: reiniciar opencode.

## Verificacion (skill `verification`)

Verificar SIEMPRE con el sistema determinista, no a ojo ni razonando. Skill
`~/.config/opencode/skills/verification/`; atajo `verify` (`~/.local/bin/verify`).

- Tras editar: `verify auto <archivo...>` (exit 0 PASS / 1 FAIL / 2 ERROR). `--quiet`
  solo imprime fallos; `--activate` permite efectos (restart shell, hyprctl reload).
- Dominios: `quickshell`, `hyprland`, `systemd`, `audio`, `code`, `syntax`,
  `packages`, `obsidian`, `tauri`, `hypr3d`. Ver `verify list`.
- Dominio nuevo: `verify scaffold <dominio> "<glob>"` (crea verifier + lo registra);
  luego implementar checks y correr `verify selftest`.
- Hook `verify-hook.js` corre `verify auto --quiet` tras cada edit/write y anexa el
  resultado al output del tool (solo si falla). No duplica `.qml` (eso lo hace
  `qml-ux-lint`).
- Regla: no cerrar una tarea sin `verify auto` en lo tocado y sin `verify selftest` si
  se cambiaron verifiers.

## Margenes UX de widgets de barra (linter)

REGLA DURA al crear/editar cualquier `BarWidget.qml` (Omarchy, `~/.config/omarchy/plugins/`):

- Padding horizontal externo >= 8px: `readonly property real hPad: Style.spaceReal(8.75)` y
  `implicitWidth = contenido + hPad*2`. `Style.space()` interno NO cuenta como padding externo.
- El contenido NO llena la altura: `implicitHeight: root.barSize` y contenido <= `barSize - 7px`.
- Todo MouseArea con `hoverEnabled: true`; animaciones <= 500ms.
- El hot reload NO repinta plugins: verificar con `omarchy restart shell` + screenshot (`grim`).

Linter instalado: `~/.local/bin/omarchy-qml-lint` (o `--all`). El plugin `qml-ux-lint` lo corre
automaticamente al editar QML bajo `~/.config/omarchy/` o `~/.config/quickshell/` y agrega el
resultado al output del tool. Corregir TODO `ERROR` (`bar-padding`, `bar-fill`) antes de terminar.

## Invariante: toda entrada/salida de UI se anima (fade/transicion)

REGLA DURA, global a TODAS las aplicaciones del usuario (web, nativa, Tauri, QML):
**ningun elemento aparece o desaparece abruptamente**. Toda aparicion/desaparicion de un
elemento de UI —por mas chico que sea: badge, chip, caption, fila, tarjeta, toast, tooltip,
menu, overlay— usa **fade/transicion**; nunca un salto seco de `display`/`visibility`/insercion
en el DOM sin animar. Al montar/desmontar listas animar entrada y salida (fade + transform
sutil); al alternar visibilidad, transicionar `opacity`/`transform`, no cortar en seco.

Limites: animaciones <= 250ms, sutiles; y SIEMPRE respetar
`@media (prefers-reduced-motion: reduce)` (desactiva la animacion, nunca la logica).

- Dueño: agente `ui-ux` (evaluacion) + owner del dominio que la implementa.
- Verificacion: dominio `agents`, check `motion-policy` (falla si esta regla desaparece de
  este archivo); la rubrica `ui-ux-scorer` la incluye como criterio penalizado.

## UI/UX: scorer del gusto visual (skill `ui-ux-scorer`)

Toda evaluacion de UI/UX (diseno nuevo, rediseno, o "como se ve esta pantalla") pasa por el
agente `ui-ux` y su skill `~/.config/opencode/skills/ui-ux-scorer/`.

- **Rubrica**: puntua 0-10 en espaciado, alineacion, jerarquia, densidad, color/contraste,
  tipografia, consistencia y estados/accesibilidad. **>= 8 = aprobado**; < 8 = rediseñar.
- **Reglas duras (gusto del usuario)**: nada de contenido pegado al borde (padding interno
  >= 16px simetrico); nada de cajas enormes casi vacias; grillas que comparten ejes; fechas en
  formato humano (no ISO crudo); snippet que no repite el titulo; paleta neutra + 1 acento
  (sin arcoiris); no todo-monocromo sin jerarquia; sin divisor largo en headers; las stats no
  dominan; animaciones <= 250ms; targets >= 32px.
- **Probe determinista** (UIs web): `node ~/.config/opencode/skills/ui-ux-scorer/probe.mjs <url>`
  -> `issues` + `score`. Checks: `content-flush`, `empty-box`, `misaligned`, `font-scale`,
  `small-target`, `too-many-colors`, `reduced-motion` (animaciones sin respetar
  `prefers-reduced-motion`). Para nativas/Tauri/QML (p.ej. la barra Omarchy) el
  probe no llega: screenshot con `grim` + evaluacion por vision.
- **Verificacion**: `node .../probe.mjs --selftest` (debe dar `ok: true`) y
  `verify auto ~/.config/opencode/skills/ui-ux-scorer/probe.mjs`.
- Dueño: agente `ui-ux`. No implementa en dominios ajenos: reporta y delega
  (`omarchy-shell`, `hyprland`, ...).


## Areas de ticket (rig): agrupacion por dominio + color

Cada ticket puede llevar un campo opcional `area` que identifica su dominio y le da color en el
tablero. Es el eje de agrupacion de `rig board` (ademas de filtro). Dominios y color hex:

| area | dominio | color |
|------|---------|-------|
| `hr` | hypr-remote | `#4C9AFF` |
| `hypr` | hyprland / plugins | `#B389FF` |
| `shell` | omarchy-shell / QML | `#FFB84C` |
| `audio` | PipeWire / WirePlumber | `#4CD9A0` |
| `meta` | rig / agentes / herdr / doctrina | `#8A8F98` |
| `infra` | dotfiles / systemd / packages | `#FF7A85` |
| `foldertinder` | foldertinder | `#7ADBFF` |
| (sin area) | — | `#8A8F98` |

- **CLI**: `rig ticket add ... --area A`, `rig ticket set <id> --area A`,
  `rig ticket list --area A` (filtro; `--area none` = sin area). `rig ticket backfill`
  rellena por prefijo/proyecto los tickets sin area (HR* -> hr, HYPR* -> hypr, FT-* ->
  foldertinder, M-*/META-*/WEB-RESEARCH -> meta, resto por proyecto) y ademas asigna `num`.
- **Numero (`num`)**: campo entero secuencial por orden de creacion (1, 2, 3...), asignado por
  `rig ticket backfill` en la migracion y por `rig ticket add` en altas nuevas. Se muestra como
  prefijo `#12` en `rig board` y `rig ticket list`. `rig ticket set|done|rm|metrics` aceptan tanto
  el slug interno (`id`) como el numero (`#12` o `12`); branch/worktree siguen usando el slug, que
  no cambia.
- **Titulo descriptivo (REGLA)**: `rig ticket add` rechaza titulos de menos de 6 palabras. El
  titulo es una frase en espanol que explica el trabajo (ej. "Navegacion herdr: espacios, tabs y
  agentes"); el slug queda solo como identificador interno, nunca como titulo.
- **Render**: `rig board` agrupa por area con una cabecera coloreada (barra + nombre del area) y
  prefija cada fila con `#num`. `rig board --plain` = salida plana, sin color ni agrupacion (para
  pipes). Las columnas son de ancho fijo y el titulo se trunca al ancho de la terminal: sin
  desbordes.
- **Contrato compartido (NO romper)**: `rig board --porcelain` y `rig ticket list --porcelain`
  exponen `area` + `color` + `num` por ticket (aditivo). Los consume el cockpit `agentes-platform`
  y la silla de trazabilidad. No cambiar la forma existente.
- **herdr**: el tab del ticket usa el color de su area cuando la version lo permite; herdr 0.8.2
  no tiene color por tab, asi que el area se muestra como etiqueta/emoji de color en el label.
- Dueño: `supervisor` (doctrina) + `dotfiles` (script). Verificacion: `verify run rig`
  (`tickets-area`, `area-add`, `area-valid`, `area-cli`, `area-color`, `area-porcelain`,
  `board-area`, `board-plain`, `tickets-num`, `tickets-title`, `num-resolve`, `title-valid`)
  + `rig --selftest`.

## Central de trazabilidad (rig central)

Un comando materializa un workspace herdr **CENTRAL** con la trazabilidad viva en 5 panes:

```
rig central
```

- **panes**: `events` (`rig events --watch`, el protagonista: el feed de todo lo que
  hacen los agentes), `board` (`rig board --watch`), `scan` (`rig scan --watch`),
  `agents` (`rig agents --watch`), `queue` (`rig queue --watch`).
- Idempotente: si CENTRAL ya existe solo lo enfoca. `--rebuild` lo cierra y recrea;
  `--no-focus` no roba el foco; `--interval SEG` ajusta el refresco; `--label`/`--cwd`
  cambian nombre/directorio (default `CENTRAL` / `$HOME`, override `RIG_CENTRAL_CWD`).
- Vive en el server de herdr: sobrevive a cerrar la terminal y se reabre con el mismo
  comando. Requiere herdr disponible (`RIG_HERDR=1`).

Comandos de la vista viva:

- `rig agents [--watch] [--porcelain] [--interval SEG]`: por silla, agente + estado
  `working|idle|blocked` + **fuente**. `source=plugin` = estado reportado por herdr
  (snapshot `pane.agent_status`); `source=derive` = inferido del contenido del pane cuando
  el panel de agentes de herdr no tiene datos (fallback robusto, nunca pane vacio).
  `--porcelain` = JSON array `{seat,agent,state,source,pane,activity}`.
- `rig queue [--watch] [--porcelain] [--interval SEG]`: cola accionable (`blocked` luego
  `pending`) + ultimos cierres `done` con evidencia (limite `RIG_QUEUE_DONE`, default 8).
  `--porcelain` = `{pending:[], blocked:[], done:[]}`.
- `rig scan` / `rig board` suman `--watch` (refresco vivo, `--interval` default 2; no
  combinan con `--porcelain`).

Dueño: `supervisor` (doctrina) + `dotfiles` (script). Verificacion: `verify run rig`
(checks `scan-watch`, `scan-watch-guard`, `agents-cli`, `agents-porcelain`, `queue-cli`,
`queue-porcelain`, `central-cli`) y `rig --selftest`.

## Objetivo permanente: trazabilidad total (event log `rig events`)

**Objetivo de ahora en adelante**: ninguna delegacion, delta, cambio de ticket ni decision
queda invisible. Todo lo que hacen los agentes deja un **evento** y se ve en la central en
vivo. Si una accion no deja evento, es un hueco que hay que cerrar.

- **Store**: `~/.local/state/rig/events.jsonl`, **append-only**, escritura bajo `flock`
  (`RIG_EVENTS_LOCK`), una linea JSON por evento con `ts` (ISO), `kind`, `actor`
  (`main` | silla | `usuario`), `ticket`, `seat`, `area`, `summary` (espanol legible), `data`.
- **Emision automatica**: los comandos que mutan estado emiten solos — `spawn` (`spawn`),
  `send` (`send`, con el resumen del mensaje delegado: eso es lo que el usuario quiere ver),
  `ticket add/set/done/rm` (`ticket-add`/`ticket-set`/`ticket-done`/`ticket-rm`),
  `work new/finish/rm` (`work-new`/`work-finish`/`work-rm`), `herdr sync` (`herdr-sync`) y
  abrir la central (`log`). Nunca rompen el comando: emiten fail-soft.
- **Actor sin tool de rig**: `rig log "<mensaje>" [--ticket X] [--seat S] [--kind K]`
  registra decisiones, diagnosticos y hallazgos (`main` lo usa con `bash`).
- **Buzon de salida de main**: `rig say "<mensaje>" [--to telegram|hub|app] [--ticket X]
  [--thread ID]` escribe un evento `kind=reply` con `actor=main` en el **mismo** store (no hay
  archivo aparte): asi `main` le responde al usuario por fuera de la terminal. El puente de
  mensajeria (ticket MAIN-BRIDGE), la app y el hub web lo consumen con
  `rig events --kind reply --since 10m --porcelain` (ordenado, JSON lines). `--to` default
  `telegram` y viaja en `data.to` junto al texto (`data.message`, `data.len`); `--thread` fija
  `data.thread`, el hilo destino (lo usan el puente de Discord y la app).
- **Vista viva**: `rig events [--watch] [--interval SEG] [--ticket X] [--seat S] [--kind K]`
  `[--since 30m] [--limit N] [--porcelain]`. Render legible por hora, coloreado por area
  (proyecto), sin desbordar el ancho. `--porcelain` = JSON lines (para el hub web);
  `--watch` refresca en el lugar (Ctrl-C restaura); no combinan entre si.
- **Rotacion**: si el feed supera `RIG_EVENTS_MAX_BYTES` (default 5MB) rota a
  `events-YYYYMMDD.jsonl` y sigue; nunca se pierde una linea (la vista lee todos los archivos).
- **Central**: `rig central` abre el workspace CENTRAL con el feed como pane prominente
  (`events`) + `board`/`scan`/`agents`/`queue`.
- Dueño: `supervisor` (doctrina) + `dotfiles` (script). Verificacion: `verify run rig`
  (checks `events-append`, `events-shape`, `events-porcelain`, `events-watch-guard`,
  `events-cli`, `log-cli`, `say-cli`, `say-to-guard`, `say-reply`, `say-to-app`,
  `central-events`) + `rig --selftest` + `verify selftest`.

## Regla: reporte verificado (re-consultar la fuente en el momento)

Antes de informar cualquier estado al usuario, **re-consulta la fuente en ese momento** y
cita cada cifra y estado con su hora y su fuente. **Prohibido reportar de memoria o de una
lectura vieja.**

- Fuentes: el store de tickets (`rig ticket show <id>` / `rig board`), el event log
  (`rig events`) y el estado de las sillas (`rig scan` / `rig seats`). Se re-leen justo antes
  de hablar, no antes.
- Formato de cita: cada dato con su valor + hora + origen (p.ej. "ticket #12 in-progress,
  leido de `rig board` a las 14:07"). Si un dato no se pudo re-consultar, dilo; no lo inventes.
- Motivo: el usuario trabaja muchas cosas en paralelo y una lectura vieja produce caos (caso
  real: una silla cerro y verifico un ticket mientras el usuario todavia lo veia trabado).
- Dueño: `supervisor`. Verificacion: dominio `agents`, check `report-policy`.

## Invariante: agentes-platform es la fuente de verdad del usuario (canal unico)

La app **agentes-platform** (el cockpit de agentes y tickets) es la **fuente de verdad del
usuario y su unico canal para ver estado y evidencia**. `main` y los agentes **NO le piden al
usuario verificar corriendo comandos de terminal** (`rig board`, `rig ticket show`, `rig scan`,
etc.): el estado de los tickets, las sillas, la evidencia y los cambios **se le muestran en la
app**.

- **Prohibido** delegar la verificacion al usuario con un comando: nada de "corre `rig board`
  para ver" ni "verifica con `rig ticket show <id>`". El comando es plomeria de los agentes; el
  usuario lee la app, no la terminal.
- **Hueco = ticket**: si algo que el usuario necesita ver no aparece en la app, eso es un
  **hueco**: se abre ticket para agregarlo a la vista, no se improvisa un comando como salida.
- **Materializacion de la vista**: la vista que expone estado y evidencia vive en
  **PLATAFORMA-BITACORA-CAMBIOS (#182)**; este invariante es su base de doctrina.
- Dueño: `supervisor` (doctrina) + `app-architect` (vista en la app). Verificacion: dominio
  `agents`, check `app-channel-policy` (falla si esta regla desaparece de este `AGENTS.md`).

## Reparto de roles: conversar con main, observar en herdr

HABLAR con el usuario es el canal de conversacion: **main** (y el puente a Discord con sus
hilos, mas el hub para lectura comoda). OBSERVAR el trabajo es **herdr**, el observatorio:
un espacio por cosa, una ventana por agente, y las vistas vivas de `rig central` (eventos,
tablero, scan, agentes, cola y la ficha por ticket). La terminal es donde trabajan los
agentes, no donde el usuario conversa.

Estado real de herdr (para no reportarlo mal):

- Los espacios de herdr ya se nombran con el numero y el titulo del ticket (#93, #94, ...).
- El estado por silla se ve bien con `rig agents` (lo deriva del contenido del panel,
  `source=derive`).
- El panel nativo de agentes de herdr sigue vacio (`herdr agent list` devuelve lista vacia)
  porque nuestros paneles corren tmux adentro y herdr ve tmux, no un agente. Es una
  **limitacion conocida**, no un bug abierto, salvo que el usuario lo pida.

- Dueño: `supervisor`. Verificacion: dominio `agents`, check `observe-policy`.

## Canal conversacional de la app: Hilos de agentes-platform

La app agentes-platform tiene la vista **Hilos**: el usuario escribe ahi y **main** responde,
sin terminal de por medio. El circuito completo:

- La app escribe el mensaje como evento `conv-in` en `~/.local/state/rig/events.jsonl` y lo
  entrega con `rig send main-seat "[app] t=<threadId> <texto>"`.
- `main` corre como **silla residente** `main-seat`: la levanta y la repone
  `rig-main-seat.service` (unidad de usuario) y `tmux-reap.sh` la exime del reaper. Al recibir
  `[app] t=<id> ...` responde `rig say "<respuesta>" --to app --thread <id>`: el evento
  `kind=reply` con `data.thread` cae en el hilo correcto y la app lo muestra.
- Si la entrega falla (silla caida), la app muestra un **aviso visible** en el hilo; la
  entrega no falla en silencio.
- Dueño: `supervisor` (doctrina) + `dotfiles` (silla y unidad). Verificacion: `verify run
  agents` (check `app-reply-policy`) + `verify run rig` (check `say-to-app`) + `verify auto
  rig-seat-keep` (selftest + shellcheck).

## Registro versionado de agentes (agents-registry)

Todo agente, skill y plugin de esta maquina queda versionado y consultable desde cualquier
agente. La herramienta es `agents-registry` (fuente `~/dotfiles/linux/bin/agents-registry`,
symlink `~/.local/bin/agents-registry`; Node, **solo lectura**: nunca modifica agentes, skills
ni plugins). Es un script propio, NO un subcomando de `rig` (rig tiene sus propios escritores).

- **Catalogo**: `agents-registry build` escribe un JSON de esquema estable y aditivo
  (`schema: 1`) con una entrada por agente, skill y plugin. Cada entrada lleva: `kind`,
  `name`, `path`, `hash` (sha256 = la version), `version` (12 chars), `mtime`, `git`
  (commit/fecha/autor/asunto del ultimo cambio), `mode`, `model` (`declared` + `effective`
  leido de la DB), `description`, `triggers`, `skills_referenced`, `permission`, `tools`,
  `harness` (integracion herdr), `verification` (dominio + estado), `tickets`
  (`owner` + `worked`) y `usage` (tokens/costo/tiempo por sesion, solo agentes).
- **Versionado estilo git**: cada build guarda una foto **append-only** en
  `~/.local/state/rig/agents/snapshots/catalog-<ts>.json` (y el ultimo en
  `~/.local/state/rig/agents/catalog.json`). Si el hash de un agente o skill cambia respecto
  de la foto anterior, emite un evento `kind=agent-change` en el feed
  (`~/.local/state/rig/events.jsonl`) con `from`, `to` y el motivo (asunto del commit). El
  feed de la central muestra "el agente X subio de version" sin que nadie lo escriba a mano.
- **Indice legible y versionado**: genera `docs/agents.md` en el repo de dotfiles (una linea
  por agente con nombre, modelo, skills, version y fecha del ultimo cambio) mas el protocolo
  de auto-mejora. Ese archivo **si se commitea**: el git de dotfiles guarda el historial de
  los agentes.
- **Comandos**: `agents-registry build` (construye el catalogo, guarda foto e indice),
  `list` (agentes/skills/plugins con version y ultimo cambio), `show <nombre>` (detalle),
  `history <nombre>` (versiones con su motivo: commits + eventos), `diff` (que cambio desde la
  ultima foto). Salida estable para maquinas con `--json`/`--porcelain`; la salida humana dice
  en castellano version, ultima modificacion y que cambio.
- **Auto-mejora (protocolo)**: cualquier agente propone un cambio sobre un agente o una skill
  mediante un ticket (`--area meta --owner supervisor`) que declara **motivo**, **evidencia**
  (fallos/loops repetidos, consumo alto medido en `opencode.db`, un hueco de razonamiento visto
  en una conversacion exportada, o un check de `verify` roto) y su **verificacion**. Al
  integrarse, el registro guarda la version anterior y la nueva con la razon (commit + evento
  `agent-change`). El catalogo es de **solo lectura para los agentes**: se regenera, no se
  edita a mano.
- **Cockpit**: `~/developing/agentes-platform` consume el catalogo (JSON estable) en vez de
  re-descubrir agentes; ese repo no se edita desde aca.
- Dueño: `supervisor` (doctrina) + `dotfiles` (script). Verificacion: `verify run agents`
  (checks `registry-tool`, `registry-catalog`, `registry-change`, `registry-doc`,
  `registry-policy`) + `agents-registry --selftest` + `verify selftest`. Config nueva **no se
  hot-reloadea**: reinicia opencode.

