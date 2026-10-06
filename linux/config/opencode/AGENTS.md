<!-- caveman-begin -->
Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra|wenyan
Stop: "stop caveman" or "normal mode"

Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused. Resume after.

Boundaries: code/commits/PRs written normal.
<!-- caveman-end -->

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
desde el hilo principal: delega con la tool `task` (`subagent_type: omarchy-shell`) o cambia
a ese agente.

## Enrutamiento por dominio: agentes owners

Cada dominio de sistema tiene UN agente **dueño**. `build` (y cualquier agente primario,
incluido el hilo principal) **NO implementa** cambios de un dominio con owner: **delega** con
la tool `task` (`subagent_type: <owner>`) o cambia a ese agente. Los owners tienen
`mode: all`, asi que build ya los ve y puede invocarlos.

| Dominio | Agente owner | Alcance |
|---------|--------------|---------|
| Quickshell / Omarchy shell | `omarchy-shell` | barra, widgets, paneles, overlays, menus, OSD, notificaciones, lock, idle, `shell.json`, plugins y QML bajo `~/.config/omarchy/` |
| Hyprland + plugins | `hyprland` | `hyprland.lua` y modulos, keybinds, monitores, input, animaciones, window/layer rules, autostart, hyprpaper, hypridle/hyprlock, hyprexpo (overview 3D), hyprpm |
| Audio (PipeWire / WirePlumber) | `audio` | ducking por voz (pw-duck), `~/.config/pw-duck/`, volumen/mute, sinks/sources, rutas de streams, dispositivo de salida, perfiles, EasyEffects/LSP |
| Meta: agentes / eficiencia | `supervisor` | auditar agentes, plugins, skills, sesiones, fallbacks de modelo, loops |
| Dotfiles / maquina | `dotfiles` | repo `~/dotfiles/`, symlinks `~/.local/bin/`, units systemd de usuario genericas, scripts de mantenimiento, skill `verification`, paquetes de sistema (`pacman`/`yay`/AUR) |
| Computer use | `computer-use` | automatizacion de GUI/escritorio |
| UI/UX (evaluacion visual) | `ui-ux` | puntuar/diagnosticar cualquier UI o screenshot contra el gusto visual del usuario (skill `ui-ux-scorer`); NO implementa, reporta y delega al owner del dominio |

Si un pedido toca un dominio **sin owner**, eso es un hueco: crea el owner antes de tocar
nada (ver regla meta).

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
- **Auto-captura de conversaciones (REGLA)**: cuando el usuario entra y pregunta,
  razona o piensa algo (no una orden mecanica de accion, sino una pregunta o
  reflexion), capturar SIEMPRE la conversacion como nota ADEMAS de responder — sin
  esperar a que lo pida. Elegir `tipo` segun el contenido y destilar la tesis + lo
  util, no transcribir literal.
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
  `small-target`, `too-many-colors`. Para nativas/Tauri/QML (p.ej. la barra Omarchy, Noteriv) el
  probe no llega: screenshot con `grim` + evaluacion por vision.
- **Verificacion**: `node .../probe.mjs --selftest` (debe dar `ok: true`) y
  `verify auto ~/.config/opencode/skills/ui-ux-scorer/probe.mjs`.
- Dueño: agente `ui-ux`. No implementa en dominios ajenos: reporta y delega
  (`omarchy-shell`, `hyprland`, ...).

