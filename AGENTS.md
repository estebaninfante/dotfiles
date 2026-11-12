# AGENTS.md — Dotfiles

## Principio fundamental

**El repositorio (`~/dotfiles/`) es la unica fuente de verdad.**

Todas las configuraciones gestionadas viven aqui. Los archivos en `~/.config/`, `~/.bashrc`, etc. son enlaces simbolicos que apuntan a este repositorio.

**El usuario esta en Omarchy (Arch Linux), NO en NixOS.** El setup declarativo con NixOS se elimino del repo (queda solo en el historial de git): NO existe `flake.nix`, `nixos-rebuild`, `home-manager` ni specialisations. Paquetes con `pacman` + `yay` (AUR).

## Filesystem del usuario (fuera del repo)

Una sola forma de nombrar las cosas. Si algo cambia, cambia aca primero.

| Ruta | Qué vive ahí | Regla |
|------|--------------|-------|
| `~/Proyectos/` | **única** raíz de código (repos git, un checkout por origin) | no crear otra raíz (`developing`, `Projects`, `proyectos`, `dev`, `Work`) |
| `~/Proyectos/_archivo/` | repos dormidos o absorbidos (siguen siendo git) | cold storage, no se edita |
| `~/Proyectos/.rig-worktrees/` | worktrees de agentes (efímeros) | viven mientras vive su ticket; `rig ticket done` los retira |
| `~/Archivo/` | datos fríos: libros, backups de teléfono, investigación, material | no es zona de trabajo |
| `~/Descargas/` | única carpeta de descargas (XDG) | `~/Downloads` no existe |
| `~/Escritorio/` | bandeja de entrada de lo que se toca hoy | debe quedar vacío al cerrar el día |
| `~/Imágenes/` | fotos y capturas | capturas nuevas van a `Imágenes/screenshots/` |
| `~/alicia/`, `~/ai-chats/`, `~/books/`, `~/go/` | vault de notas, historial de chats, biblioteca, GOPATH | excepciones conocidas en `doctor.sh` |

Reglas que mantienen el orden (las verifica `scripts/doctor.sh`):

- **Nada de backups al lado del original.** Los `.pre-dotfiles.*` van a
  `~/.local/state/dotfiles-backups/`; los de `~/.local/bin` no existen.
- **Nada de archivos sueltos en `$HOME`.** Ni logs, ni PNG, ni `.part`.
- **`~/.config/user-dirs.dirs` se GENERA** desde `linux/config/user-dirs.dirs.template`
  (no se symlinkea: `xdg-user-dirs-update` lo reescribe).
- **El `$HOME` no es un rootfs.** Si aparece `usr/`, `etc/`, `var/`, `bin/` en `$HOME`,
  es basura de un chroot y se borra (requiere `sudo`).
- **Un `git worktree` por agente, no un ticket eterno**: al cerrar el ticket se retira.


## Reglas permanentes

1. **Editar siempre dentro de `~/dotfiles/`.** Nunca modificar directamente `~/.config/`, `~/.bashrc` u otros destinos enlazados. Excepcion: migraciones puntuales o emergencias justificadas.

2. **Antes de crear un script nuevo, comprobar si uno existente puede reutilizarse o extenderse.** No duplicar funcionalidad.

3. **Evitar duplicar logica.** Si un patron se repite, abstraerlo en una funcion.

4. **Usar cambios minimos.** No reescribir archivos completos sin necesidad. Usar `edit` con precision quirurgica.

5. **Antes de modificar una configuracion existente, revisar el repositorio primero.** Respetar personalizaciones existentes del usuario.

6. **Nada de NixOS.** No crear `flake.nix`, ni ejecutar `nixos-rebuild`/`home-manager`. Todo va directo a `~/.config/` o `~/.local/bin/` via symlink al repo.

## Estructura del repositorio

```
dotfiles/
├── linux/
│   ├── config/          # ~/.config/ (symlinked)
│   ├── home/            # ~/.bashrc, ~/.gitconfig
│   ├── bin/             # ~/.local/bin/ (scripts propios)
│   ├── voice/           # TTS daemon + Chatterbox server
│   ├── xkb/             # Layout de teclado XKB
│   ├── patches/         # patches (lan-mouse AltGr, waybar Lua dispatch)
│   └── system/          # keyd, NetworkManager (dispatcher + kvm-ensure), systemd, sysctl
├── windows/
│   └── lan-mouse/       # config de LAN Mouse + setup-lan-mouse.ps1 (4 escenarios)
├── scripts/
│   ├── setup-omarchy.sh # fresh install en un comando
│   ├── link-dotfiles.sh # aplica el inventario de symlinks (idempotente)
│   ├── detect-machine.sh# detecta laptop/desktop por hardware
│   ├── omarchy-sync.sh  # export/import config del shell Omarchy (barra/plugins)
│   ├── setup-tts.sh     # TTS
│   ├── setup-kokoro-reader.sh # Read Aloud de Zotero (Kokoro local)
│   ├── reconcile-machine.sh   # aplica a la maquina lo que pide el repo (autosync)
│   ├── setup-secrets.sh # Configura/verifica claves y secrets
│   ├── publish.sh       # ÚNICO dueño de commit+push (--yes para agentes)
│   └── doctor.sh        # sanidad del filesystem + repo (symlinks, worktrees, raíces)
├── AGENTS.md
└── README.md
```

Los secrets locales viven en `~/.config/dotfiles-secrets.sh` (FUERA del repo,
sourced por `~/.bashrc`). Nunca commitear claves.

## Inventario de configuraciones gestionadas

### Linux config (`linux/config/`) — directorios completos

| App | Ruta destino |
|-----|-------------|
| hypr | `~/.config/hypr/` |
| waybar | `~/.config/waybar/` |
| kitty | `~/.config/kitty/` |
| nvim | `~/.config/nvim/` |
| kanata | `~/.config/kanata/` |
| fastfetch | `~/.config/fastfetch/` |
| mako | `~/.config/mako/` |
| swaync | `~/.config/swaync/` |
| swayosd | `~/.config/swayosd/` |
| avizo | `~/.config/avizo/` |
| btop | `~/.config/btop/` |
| gh | `~/.config/gh/` |
| opencode | `~/.config/opencode/` |
| quickshell | `~/.config/quickshell/` (bar + menus + launcher) |
| tmux | `~/.config/tmux/` |
| gesturecontrol | `~/.config/gesturecontrol/` |
| voice | `~/.config/voice/` (config TTS) |
| input-remapper-2 | `~/.config/input-remapper-2/` (copiado, no symlink) |

### VS Code (caso especial)

Solo se enlazan `settings.json` y `keybindings.json` (el resto de `~/.config/Code/User/`
lo reescribe el editor). Fuente: `linux/config/vscode/User/`. Extensiones: VSCodeVim,
Live Server, Rosé Pine. Config: vim-style (leader espacio), UI minimalista, Live Server en 8080.

### Omarchy shell (`linux/config/omarchy/` — copiado, no symlink)

La barra activa es la de **Omarchy**, no la de dotfiles. Su config vive en
`~/.config/omarchy/` y se versiona aqui: `shell.json` (barra `eztvn.bar`, layout,
`centerAnchor`), `shell.toml` (fuente/scrim), `bar/modules/services.qml`,
`branding/`, `extensions/omarchy-menu.jsonc`, `backgrounds/` (fondos propios),
`hooks/*.hook` y los plugins locales (`plugins/eztvn.*`,
`talk-command.status`). Los plugins/temas instalados por git NO se copian (peso
+ `.git`): sus id+url viven en `plugins-git.txt` / `themes-git.txt` y se
reinstalan con `omarchy plugin add` / `omarchy theme install`.

`scripts/omarchy-sync.sh export` (maquina personalizada) y `import`
(laptop/fresh) replican. `setup-omarchy.sh` Fase 10.5 corre `import`
automaticamente. No symlinkear `~/.config/omarchy`: Omarchy escribe ahi en vivo.

**Auto-sync (para que no se desincronice):** `scripts/dotfiles-sync.sh` (timer
`dotfiles-sync.timer`, cada ~5 min en ambas maquinas) publica y sincroniza, en
este orden: **export -> commit -> pull -> import (si vino shell del otro) ->
push**. Nada se pierde y ninguna maquina pisa a la otra:

1. `export` de la config viva de Omarchy al repo (aditivo: nunca borra).
2. `git add -A` + commit automatico de TODO cambio, aunque este a medias
   (`autosync(<host>): <fecha>`).
3. `git pull --rebase=merges --autostash` para integrar lo del otro equipo.
4. Si el pull cambio `linux/config/omarchy/`, se corre `import` a la config viva
   (seguro: lo local ya quedo exportado y commiteado en 1-2).
5. `git push`.

Ante conflicto de rebase: aborta, notifica y **no** importa. La bandera de
pausa es `~/.config/dotfiles-autosync.off` (menu de la barra: Dotfiles >
Auto-sync). Verificacion manual: `omarchy-sync.sh status` reporta `DRIFT` si el
live difiere del repo. Machine-specific: `shell.<machine>.json`
(laptop/desktop) gana sobre `shell.json` si existe; hoy no se usa.

**Regla para agentes:** despues de tocar la config viva de Omarchy
(`~/.config/omarchy/`) o cualquier archivo del repo, correr
`~/dotfiles/scripts/dotfiles-sync.sh --force` (o `publish.sh`) para no depender
del timer. Ver skill `dotfiles-publish`.

### Linux config — archivos sueltos

| Archivo | Ruta destino |
|---------|-------------|
| libinput-gestures.conf | `~/.config/libinput-gestures.conf` |
| mimeapps.list | `~/.config/mimeapps.list` |
| user-dirs.dirs **generado** desde `user-dirs.dirs.template` (no symlink) | `~/.config/user-dirs.dirs` |
| user-dirs.locale | `~/.config/user-dirs.locale` |

### Pi agent (`linux/pi/agent/` — symlink por archivo)

Solo se versionan extensiones propias de Pi y su config. El resto de `~/.pi/agent/`
(sesiones, auth, skills de terceros) no se toca.

| Archivo | Ruta destino |
|---------|-------------|
| extensions/rig.ts | `~/.pi/agent/extensions/rig.ts` |
| extensions/worktrees.ts | `~/.pi/agent/extensions/worktrees.ts` |
| extensions/lib/ | `~/.pi/agent/extensions/lib/` (helpers puros, sin `index.ts`) |
| extensions/tts-summary.ts | `~/.pi/agent/extensions/tts-summary.ts` |
| extensions/conversar.ts | `~/.pi/agent/extensions/conversar.ts` |
| extensions/buscar-web.ts | `~/.pi/agent/extensions/buscar-web.ts` |
| extensions/herdr-agent-state.ts | `~/.pi/agent/extensions/herdr-agent-state.ts` |
| settings.json | `~/.pi/agent/settings.json` |
| worktrees.json | `~/.pi/agent/worktrees.json` |

La extension de voz es solo un cliente de `voice avisar --source Pi`: la logica de
voz, perfiles y registro vive en el sistema de voz (`linux/voice`), no en Pi, para
que cualquier proceso la use igual.

Cambios en una extension se aplican con `/reload` (o reiniciando Pi).

Cierre hablado (`extensions/tts-summary.ts`): al asentarse la corrida se dice una
frase (el aviso del agente o un resumen de respaldo). Si el usuario interrumpio,
no se dice nada: se mira `agent_settled.aborted`, el `stopReason` de los turnos
(`message_end`/`turn_end`) y el silencio dura hasta el proximo pedido, asi que un
cierre que se estaba generando en segundo plano tampoco suena. El respaldo que
lee la sesion solo acepta texto escrito en esa misma corrida (antes rescataba
trabajo viejo y lo repetia por voz al cortar). Reglas puras en
`extensions/lib/tts-cierre.ts`. Verificador: `scripts/verify/voz-cierre.sh`.

#### Un worktree por agente (`worktrees.json` + `extensions/worktrees.ts`)

Dos agentes en la misma carpeta se pisan: uno borra el archivo que el otro lee y un
`git add -A` se lleva trabajo ajeno. Por eso cada agente trabaja en su propio git
worktree (carpeta y rama propias) y lo mergea al terminar.

`worktrees.json` decide el flujo de cada proyecto:

| Flujo | Qué significa |
|-------|----------------|
| `main` | worktree obligatorio; base y merge en la rama principal (o la de `rama`) |
| `developing` | worktree obligatorio; base y merge en la rama de desarrollo |
| `directo` | se edita en el lugar, sin worktree (dotfiles y configs que la maquina lee del repo) |

Un repo que no esta en la lista usa `flujoPorDefecto` (`main`). La extension pone
las reglas en el system prompt de cada turno, **bloquea** `write`/`edit` y los
comandos bash que escriben en la copia principal (con motivo y escape: `/worktrees
libre` o `PI_SIN_WORKTREES=1`), le da un worktree propio a cada subagente, y expone
la tool `worktree` (`abrir` / `lista` / `cerrar`). Los worktrees viven en
`<parent del repo>/.rig-worktrees/<repo>/<id>`, la misma convencion que `rig work`.

`rig work new` tambien saca su rama base de este archivo: un solo lugar decide el
flujo de cada proyecto. Verificador: `scripts/verify/ramas.sh`.

### OMP agent (`linux/omp/agent/` — symlink por archivo)

OMP (oh-my-pi, fork de Pi, comando `omp`) usa `~/.omp/agent/`. Solo se versiona
su config. Las credenciales viven en `~/.omp/agent/agent.db` (SQLite, local a la
maquina) y **nunca** van al repo: se recrean con `omp login opencode-go` o
`omp auth import creds.json`.

| Archivo | Ruta destino |
|---------|-------------|
| config.yml | `~/.omp/agent/config.yml` |
| AGENTS.md | `~/.omp/agent/AGENTS.md` (→ regla global, ver abajo) |

Proveedor por defecto: `opencode-go` (`modelRoles.default`). OMP escribe sobre el
symlink sin romperlo, asi que `omp config set` desde la maquina termina en el repo.

### Regla global de ideas (`linux/agents/` + `linux/claude/`)

Una sola regla para todas las IAs. El texto canónico es
`linux/agents/estandar-ideas.md`: toda idea o pendiente que el usuario suelta en
el chat se captura en el vault `~/alicia` (`alicia nuevo`), no en el chat ni en el
store viejo `~/.local/share/pi/ideas/`. Los tickets de trabajo van a
`agent-os-cli`.

| Archivo del repo | Ruta destino | Lo lee |
|------------------|--------------|--------|
| linux/omp/agent/AGENTS.md | `~/.omp/agent/AGENTS.md` | OMP (contexto de usuario) |
| linux/claude/CLAUDE.md | `~/.claude/CLAUDE.md` | Claude Code (memoria de usuario) |
| linux/config/opencode/AGENTS.md | `~/.config/opencode/AGENTS.md` | OpenCode (reglas globales) |

Los tres leen la misma regla: Claude y OpenCode por symlink directo a
`linux/agents/estandar-ideas.md`; OMP conserva sus reglas de escritorio y suma
el estándar con `@../../agents/estandar-ideas.md`. Editar solo la regla canónica
(o las reglas propias de OMP, nunca el import). Verificación:
`scripts/verify/ideas.sh`.

### Protocolo de proyectos (`linux/agents/`)

Todo proyecto nuevo pasa por DoD aprobada antes de diseñar o implementar. Las reglas
viven en `linux/agents/delegacion-claude.md` (sección "Protocolo de proyectos"), que es
lo que el DeepSeek Harness lee como `~/.dsh/AGENTS.md`; las plantillas (DoD, cierre de
sesión, ratio de tickets) y los comandos están en `linux/agents/protocolo-proyectos.md`.
El registro de empezados/terminados es `agent-os-cli` (tickets), no una lista aparte.

### Home (`linux/home/`)

| Archivo | Ruta destino |
|---------|-------------|
| .bashrc | `~/.bashrc` |
| .gitconfig | `~/.gitconfig` |

### Scripts (`linux/bin/`)

Todos los scripts propios de `~/.local/bin/` (excluye ejecutables instalados por paquetes).

`linux/bin/omp` es el wrapper de OMP: fija el pin global con `mise use -g` y
ejecuta el binario (`github:can1357/oh-my-pi`). El binario en si lo instala mise,
asi que una maquina nueva queda lista con solo correr `omp` una vez.

**Avisos de escritorio:** usar `notify` (envuelve `omarchy-notification-send` y
cae a `notify-send` si la maquina no lo tiene). Forma:
`notify -g <glifo> -u normal -t <ms> --app-name <app> "Titulo" "Cuerpo"`.
Cada script pone su glifo; el título es el hecho, no el nombre del script.

### Voice (`linux/voice/`)

| Archivo | Descripcion |
|---------|-------------|
| daemon.py | Daemon TTS con FIFO queue, administra chatterbox server |
| engine.py | Config/estado TTS (engines, idiomas, toggles) |
| chatterbox_server.py | Server persistente Chatterbox (model in GPU memory) |
| chatterbox_synth.py | Wrapper legacy (subprocess mode, fallback) |
| asr_vosk.py | Streaming ASR (Vosk CPU) para el wake-word |
| pi_shim.py | Puente Ollama->agente para la voz headless (`voice think`/`voice ptt`) |
| spoken.py | Limpia la respuesta para oído (código/HTML/markdown) |
| pi-brain/AGENTS.md | Guía del cerebro headless: cómo manejar el escritorio |
| `linux/bin/voice-asr-stream` | Selector del motor del wake-word: GPU (`[wake] gpu_command`) o CPU (Vosk) |
| `linux/bin/voice-hermes` | Hermes headless (una pasada, sólo terminal) para el cerebro de voz |
| `linux/bin/voice-pi` | Variante Pi headless (sin razonamiento/extensiones) del cerebro |
| `linux/bin/dictado` | Dictado del escritorio: graba, transcribe y escribe en la ventana enfocada |
| `linux/bin/dictado-historial` | Historial de dictados (SUPER+CTRL+I) |
| `linux/dictado/servidor.py` | Servidor STT local (faster-whisper) que usa `dictado` |
| `scripts/setup-wake.sh` | Prepara el wake-word: venv + vosk + modelo + servicio `talk-command.service` |
| `linux/voice/reader/kokoro_server.py` | Daemon Kokoro (modelo en memoria) para Read Aloud + lector standalone |
| `linux/voice/reader/kokoro_speechd.py` | Cliente de speech-dispatcher: sintetiza y reproduce con aplay |
| `linux/voice/reader/kokoro_read.py` | Lector standalone de PDF/texto (kokoro-read/kokoro-ctl) |

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Para cambios de configs symlinkeadas (hypr, waybar, nvim, etc.), se aplican al instante (symlink directo al repo).
3. Para scripts: guardar en `linux/bin/`; el inventario de `scripts/link-dotfiles.sh` los enlaza.
4. Al anadir/renombrar una config, agregarla al inventario de `scripts/link-dotfiles.sh` y correrlo.
5. Ejecutar `~/dotfiles/scripts/publish.sh` para commitear y pushear (único dueño de git).
6. Correr `~/dotfiles/scripts/doctor.sh` si tocaste rutas del filesystem o worktrees.

## Delegación a Claude Code (agentes atascados)

Cuando un problema no se resuelve tras 2-3 intentos serios (o cada arreglo rompe otra
cosa), **no seguir acumulando variantes**: delegar a Claude Code. Está cableado así:

- Regla global del harness: `linux/agents/delegacion-claude.md` -> `~/.dsh/AGENTS.md`
  (la lee DeepSeek Harness en toda sesión, en cualquier workspace).
- Skill: `linux/agents/skills/delegate-a-claude/SKILL.md` -> `~/.agents/skills/`
  (tiene el procedimiento y la plantilla del brief que funciona).
- Helper: `linux/bin/delegar-claude` (`start <brief.md> [--name X]`, `status`, `read`,
  `tail`, `list`, `stop`). Deja brief+log+pid en `~/.local/state/delegar-claude/<nombre>/`
  y desprende el proceso con `setsid` (un `nohup ... &` suelto muere con el shell).

### Plugins propios del harness (comandos `/claude` y `/skills`)

`linux/dsh/plugins/claude-visible/` es un plugin local del DeepSeek Harness (sin
dependencias: no importa nada del harness) que agrega dos comandos al chat:

- `/claude [list|status [n]|read [n]|start <brief.md>]`: ver las delegaciones a Claude
  (estado y salida, leídas de `~/.local/state/delegar-claude/`) y lanzar una.
- `/skills [<nombre>]`: listar todas las skills instaladas en `~/.agents/skills` con su
  descripción, o el `SKILL.md` de una.

Se enlaza a `~/.dsh/plugins/claude-visible` y `link-dotfiles.sh` asegura su entrada en
`~/.dsh/profiles/web/cordis.patch.yml` (forma `- insert:`) y la dependencia
`file:` en el perfil web. **El servidor del harness carga los plugins al arrancar**:
después de instalarlo hay que reiniciar con `dsh-web --restart` (o el próximo inicio).
Ojo: reiniciar el servidor corta la sesión en curso, así que no lo hagas a mitad de un
turno largo.

### `side-questions`: preguntas laterales sobre texto seleccionado

`linux/dsh/plugins/side-questions/` (host + cliente) resuelve "subrayo algo y
pregunto ahí mismo" sin ensuciar el chat: seleccionás texto en la conversación,
aparece un botón **Preguntar** pegado a la selección y la respuesta llega a un
globo flotante (`position: fixed`) que se cierra con Esc. Nada se escribe en la
sesión: no suma mensajes ni crece el transcript.

- `lib/index.js` registra `POST /side-questions/ask` en el `webServer` del
  perfil. El body lleva `{sessionId, quote, question, transcript}`; el handler
  resuelve provider/modelo de `sessions.get(id).requestHeader().config` y hace
  una llamada corta a `ctx.llm.stream` (system propio + extracto del final de la
  conversación, máx. 14k chars, 700 tokens). Exige el header
  `x-dsh-side-question: 1` (un sitio externo no puede mandarlo sin preflight).
- `lib/client.js` es DOM plano (sin React): escucha `mouseup`/`mousedown`/`scroll`
  en captura, valida que la selección esté dentro de
  `[data-conversation-scroll]` y no en un campo de texto, y pinta globo + panel
  con los tokens `--dsw-*` de la app.
- `harness.html` es la página de prueba aislada (loader simulado + `fetch` de
  mentira): abrirla en el navegador y seleccionar texto para ver la UI sin
  servidor.
- Instalado como dependencia `file:` del perfil web y entrada `- insert:` en
  `cordis.patch.yml`; se activa al reiniciar (`dsh-web --restart`). Para apagarlo,
  borrar la línea `id: local-side-questions` del patch y reiniciar.

### `path-links`: rutas del chat clicables

`linux/dsh/plugins/path-links/` (host + cliente) hace tocables las rutas que el
agente menciona (`~/dotfiles/linux/bin/agent-os-cli`, `~/.config/opencode/tickets.json`,
`Proyectos/…`), estén en un párrafo, una tabla o backticks. Clic en **archivo** →
panel lateral derecho con el preview que corresponda; clic en **carpeta** → gestor
de archivos (xdg-open); ruta inexistente → aviso abajo, sin abrir nada.

- `lib/client.js` no toca el DOM de React: en `mousemove` convierte el punto en
  un caret (`caretRangeFromPoint`), lee el token bajo el cursor, valida la
  heurística de ruta y subraya con la **CSS Custom Highlight API**
  (`::highlight(dsh-path-hover)`); el `click` manda el token al host. Ignora
  links, botones, campos de texto y selecciones activas (así no pelea con el
  globo de `side-questions`). Ojo: la variable local `CSS` de estilos shadowea el
  global; usar `globalThis.CSS.highlights`.
- `lib/index.js` resuelve en `POST /path-links/open` (header `x-dsh-path-links: 1`):
  expande `~` con `os.homedir()`, resuelve relativas contra `session.header.cwd`,
  hace `stat` y devuelve `{kind: file|dir|missing}`. El archivo viaja como
  `dsh-resource://file/session/<id>/<rel>` con la misma regla que el chat
  (`fileAddressFor`): relativo si está dentro del workspace, absoluto si no.
- `harness.html` es la página de prueba aislada (loader simulado, `fetch` falso y
  `ctx.sidebarRight` de mentira): abrirla y pasar el mouse / hacer clic.
- Instalado como dependencia `file:` + entrada `- insert:` en `cordis.patch.yml`;
  se activa al reiniciar (`dsh-web --restart`). Para apagarlo, borrar la línea
  `id: local-path-links` del patch y reiniciar.

### `machine`: la página de proyectos del harness

`linux/dsh/plugins/machine/` (host + cliente) monta una **página completa**
encima del chat con el inventario de `~/Proyectos`: resumen (cuántos sin
decisión, cuántos activos, cuántos sin tocar +30 días, cuántos con cambios sin
guardar), tabla con selector de estado por fila, y ficha al costado con hechos
del disco, nota y tareas. Se abre con la pestaña vertical `proyectos` del borde
izquierdo; se cierra con Esc o el botón.

- **La base es la fuente de verdad**: `~/.local/share/machine/machine.db`
  (SQLite, WAL). Tablas `entities` (kind, slug, title, state, note, parent_id),
  `facts` (hechos observados), `sources`, `schema_version` (migraciones
  numeradas en `MIGRATIONS` del CLI, nunca se edita una aplicada).
- **Dos capas, y no se mezclan**: los *hechos* los recalcula `machine scan`
  desde el disco (git, remoto, rama, archivos sin guardar, commits sin subir,
  systemd, `.webapp.json`); las *decisiones* (`kind`, `state`, `note`) las
  escribe el humano y `scan` **nunca** las pisa.
- **Estados**: `unclassified` · `active` · `paused` · `done` · `archived`.
  `done` solo tiene sentido en `project` y `experiment`; un `product` se pausa o
  se archiva, nunca se "termina".
- **Un solo motor**: el SQL vive en el CLI `machine`
  (`~/dotfiles/linux/bin/machine`: `init`, `scan`, `ls`, `show`, `set`,
  `task add|ls|done`, `stats`, todo con `--json`). El plugin solo lo invoca por
  `execFile`, así el panel, los agentes y la terminal leen lo mismo.
- **Rutas** del plugin: `GET /machine/projects`, `GET /machine/project?slug=`,
  `POST /machine/{scan,entity,task,task-done}`; los POST exigen el header
  `x-dsh-machine: 1`.
- Instalado como dependencia `file:` + entrada `- insert:` en
  `cordis.patch.yml` (`link-dotfiles.sh` lo asegura). **Requiere reiniciar el
  servidor** (`dsh-web --restart`) porque los clientes se componen al arrancar.
- Verificación sin tocar el servidor vivo: levantar otra instancia
  (`dsh --profile web --no-open --port 3999`), pedir `/machine/projects` y
  revisar que el manifiesto del boot incluya `dsh-local-machine`.

**Un panel en vivo sí es posible**: cada paquete `@deepseek-ai/dsh-client-ui-*`
instalado trae su bundle de cliente (`lib/client.js`, formato
`window.__ModuleLoader__.load({ id, factory })` con `exports.apply`), y el loader
del navegador lo sirve desde el perfil. Un plugin local puede traer su media
cliente declarando en `package.json` `exports["./client"]` + `dsh.client`
(`platform: web`), sin React: DOM plano basta (ver `side-questions`). Igual
necesita reinicio del servidor, porque el grafo de clientes se compone al
arrancar.

`scripts/link-dotfiles.sh` crea los tres symlinks. El brief tiene que incluir **lo ya
probado y qué resultó** y qué no se puede romper: es lo que hizo que Claude resolviera
en un intento un caso donde el agente llevaba horas.

## Multi-maquina (laptop + desktop)

### Configs machine-specific

**`hyprland.lua`** usa condicionales por machine type:

```lua
local f = io.open(os.getenv("HOME") .. "/.config/machine-type", "r")
local machine = f and f:read("*a"):match("^%s*(.-)%s*$") or "laptop"
if f then f:close() end

if machine == "laptop" then
    -- monitores, touchpad, device, lid
end

if machine == "desktop" then
    -- monitores desktop
end

-- Shared: keybinds, appearance, autostart, etc.
```

**`hyprpaper`** tiene dos configs (la ruta `path =` la reescribe
`sync-wallpaper.sh`, no editarla a mano):
- `hyprpaper.conf` -> monitor `DP-2` (desktop)
- `hyprpaper-laptop.conf` -> monitor `eDP-1` (laptop)

**El monitor vertical cuelga del desktop o de la laptop.** Es el mismo panel
(ASUSTek VG27AQL3A): se pide 2560x1440 a escala 1.25, girado (`transform 3`) y en
`0x0`, así se ve igual en las dos máquinas. En la laptop, `monitors.lua` detecta
la externa por lo que reporta Hyprland (no por nombre de puerto: da igual HDMI o
USB-C/DP), la pone a la izquierda y deja el panel interno a su derecha y centrado
(`1152x574` cuando la vertical está girada). El modo se elige del más alto que
anuncie el monitor (144 Hz con corriente, 60 con batería) y se re-aplica al
segundo de conectarse, por si todavía no anunciaba sus modos. `HEADLESS-*` (el
monitor virtual de Sunshine) no cuenta como externa. El layout acompaña al giro:
vertical = `scrolling` (franjas de 1/3), horizontal = `dwindle`.

**9 espacios por pantalla** (`linux/config/hypr/base/workspaces.lua`): la interna
es dueña de 1..9 SIEMPRE; cuando hay una segunda pantalla real, la externa usa
28..36 (los mismos 9, sin pisarse; 10 es leia/cartridges y 11..20 son de
`espacios`). Los atajos `SUPER+M/W/V/H/T/N/G/C/R` y `SUPER+SHIFT+...` apuntan a la
pantalla con foco, igual que el viaje animado de `navigation.lua`, la barra
(`plugins/eztvn.workspaces`, que calcula su base por pantalla) y la grilla de
`hyprexpo` (`workspace_method` por monitor + `max_workspace = 36`). Spotify se
re-registra al último espacio de la pantalla de trabajo (9 o 36). Números que no
se ven: la barra y el overview no rotulan, así que las dos pantallas se sienten
igual que el desktop.

**hyprexpo (overview `SUPER+Y`)**: la grilla 3D/fisheye es un parche local del
plugin (`linux/patches/hyprexpo-local.patch`) que **corre igual en laptop y
desktop**. `setup-omarchy.sh` lo compila/instala con `linux/bin/hyprexpo-rebuild.sh`
en `/var/cache/hyprpm/$USER/hyprexpo/hyprexpo.so`. `hyprland.lua` lo carga por
`hl.plugin.load(...)`. Tras `hyprpm update` hay que re-ejecutar el rebuild.
`EXPO_3D = true` en `hyprland.lua` (ver `linux/config/hypr/hyprexpo-changes.md`).

**Orientación del monitor**: el overview 3D está hecho para verse igual con la
pantalla horizontal o girada (el desktop está vertical: `DP-2` con
`transform: 1`). La grilla se proyecta en el mismo espacio que el resto del
overlay, sin recomponer el transform del monitor; si alguna vez se ve vacía con
la pantalla girada, ese es el guard que hay que mirar (`hyprexpo-rebuild.sh`
falla a propósito si el patch pierde esa línea). Para probarlo sin reiniciar la
sesión viva: `HYPREXPO_DEV_TRANSFORM=1` en el harness nested
(`~/.local/bin/hyprexpo-verify-3d.sh`) y capturar el output nested.

**Wallpaper (una sola fuente)**: el fondo canónico vive en el symlink de Omarchy
`~/.local/state/omarchy/current/background` (lo escribe `omarchy theme bg set`).
Lo propagan dos mecanismos, porque el hook `theme-set` **no** se dispara al cambiar
sólo el fondo:

- `wallpaper-sync.path` (vigila el directorio `~/.local/state/omarchy/current`) +
  `wallpaper-sync.service` → `linux/bin/sync-wallpaper.sh`: reescribe
  `hyprpaper.conf`, aplica a hyprpaper y empuja la ruta al plugin (overview).
- `wallpaper-sync.timer` (2 min): red de seguridad; si alguien aplica un fondo con
  `hyprctl hyprpaper` directo, vuelve el canónico y no quedan dos wallpapers.
- El overview resuelve el symlink y cachea por (ruta real + mtime + tamaño), así que
  un cambio de fondo se ve en la próxima apertura sin reload.

`setup-omarchy.sh` instala el hook `theme-set` (`omarchy hook install theme-set ...`)
y `install-user-units.sh` habilita los tres units. **Nunca** setear el fondo con
`hyprctl hyprpaper` directo: el timer lo revierte en <= 2 min.

### IPs LAN estaticas (fuera del pool DHCP)

- Laptop: `192.168.1.240` · Desktop: `192.168.1.241`
- La laptop tiene el WiFi en **DHCP** (`Familia_Infante_PLUS`); la IP KVM
  flotante (`192.168.1.240`) la administra `kvm-ensure.sh`, no el perfil NM.
  El desktop tiene `.241` estatica en su ethernet.
- **KVM (lan-mouse)**: `linux/system/NetworkManager/kvm-ensure.sh` deja la IP
  KVM en la interfaz **ethernet de casa** si esta conectada, si no en el WiFi
  de casa, y agrega la ruta simetrica `PEER/32 dev IFACE src KVM_IP`. El
  `dispatcher.d/90-lan-mouse` lo corre en eventos NM y el timer system
  `kvm-ensure.timer` (cada 2 min) lo re-aplica como red de seguridad. **El
  WiFi NO se baja** cuando hay ethernet: quedan las dos interfaces (el cable
  dedicado al KVM, el WiFi sigue de default route para internet y como
  respaldo si el dock USB se reenumera).
- Requiere `rp_filter` **loose** (`linux/system/sysctl/99-lan-mouse.conf`).
- La deteccion laptop/desktop es por **hardware** (`detect-machine.sh`), no por
  hostname: tras migrar de NixOS a Omarchy los hostnames son
  `laptopmarchy` / `astradeux`, y cualquier `case "$(hostname)"` con
  `laptop`/`desktop` queda muerto.
- Windows: `windows/lan-mouse/` tiene la config equivalente + `setup-lan-mouse.ps1`
  (auto-detecta laptop/desktop por bateria). Ver `windows/lan-mouse/README.md`.

### SSH entre maquinas

```bash
ssh eztvn@desktop  # desde laptop
ssh eztvn@laptop   # desde desktop
```

- Resolucion via tailscale MagicDNS
- IPs tailscale: desktop `100.118.58.7`

### Portapapeles y media entre maquinas (`clipboard-sync`)

Copiar en una maquina y pegar en la otra, sin pasos: texto, capturas
(`image/png`) y archivos (`text/uri-list`: el video de `screenrecord-toggle`,
una captura guardada, cualquier cosa copiada en Dolphin).

- Demonio `clipboard-sync.service` (unit en `linux/system/systemd-user/`, listado
  en `enabled-all.txt`): `wl-paste --watch` empuja cada cambio por SSH. Prueba
  primero la LAN (`.240`/`.241`) y cae a Tailscale si no hay ruta.
- Los archivos viajan de verdad (framing `nombre<TAB>tamano` + bytes, sin `tar`
  ni copias temporales) y quedan en `~/Descargas/Entre-computadoras/<fecha>/`.
  La uri-list se reescribe con las rutas del destino: alla se pega y funciona.
- Anti-eco: el digest (`mime` + NUL + bytes) se marca como visto ~5 min en
  `$XDG_RUNTIME_DIR/clipboard-sync/seen`; lo que vuelve se ignora. Un envio que
  falla se desmarca, asi el proximo intento no queda mudo.
- A mano: `SUPER+SHIFT+Z` empuja (repetir algo ya enviado), `SUPER+SHIFT+J`
  trae lo que tenga el otro equipo, `clipboard-sync send <ruta...>` comparte
  archivos sueltos.
- **Avisos de escritorio: silenciados a proposito.** Sacar una captura o grabar
  no debe escupir toasts: ni `shot`/`capture-menu`/`screenrecord-toggle` (se les
  quitaron los de "captura copiada"/"video copiado"/"grabando"), ni el
  portapapeles ("imagen enviada", "llegaron archivos"). Solo quedan los
  `-u critical` (no se pudo capturar) y los fallos de envio. Para recuperar los
  del portapapeles: `NOTIFY_OK=1` en `~/.config/clipboard-sync/config`.
- Registro: `~/.local/state/clipboard-sync/log`. Diagnostico: `clipboard-sync doctor`.
- Verificacion: `scripts/verify/portapapeles.sh` (corre el "otro equipo" en
  loopback: no necesita SSH ni la otra maquina; pisa el portapapeles real).

### Reglas para AI (opencode)

1. **Nunca modificar bloques `if machine == "X"` sin preguntar.** Esos bloques son machine-specific.
2. **Configs compartidas** (keybinds, appearance, animations, window rules) se pueden editar libremente.
3. **Nada de NixOS.** El setup anterior se elimino; no recrear `flake.nix` ni ejecutar herramientas de NixOS.
4. **Al agregar un script**, guardarlo en `linux/bin/` y correr `scripts/link-dotfiles.sh` (no clobbea archivos reales de Omarchy).

## TTS (Text-to-Speech)

Sistema TTS con daemon + Chatterbox (Resemble AI).

**Motor principal:** Chatterbox Multilingual V3 (0.5B params, ~3GB VRAM RTX 3070)
- Soporta 23+ idiomas incluyendo espanol
- Server persistente (`chatterbox_server.py`) mantiene modelo en GPU
- Latencia: ~0.75-0.86s synth (post-carga inicial de ~9s)
- RTF: 0.80-0.94 (mas rapido que tiempo real)

**Uso:**
```bash
voice speak "hola mundo"          # español (default)
voice lang en && voice speak "hello"  # ingles
tts "hola"                        # bash function: voice lang + voice speak
tts -en "hello world"             # ingles via bash function
```

**Toggles:**
```bash
voice on/off        # enable/disable TTS
voice status        # estado completo
voice engine X lang # cambiar motor (chatterbox/piper/espeak)
```

**Chain de fallback:** chatterbox → piper → espeak

**Cortar la voz.** `voice stop` vacía la cola y corta el `pw-play` en curso
**por PID**. Un corte no es un fallo: la frase no se reintenta con otro motor
(antes seguía sonando con piper o espeak, peor). Si el corte llega mientras se
sintetiza, la frase se descarta en vez de sonar después. Verificador:
`scripts/verify/voz-corte.sh`.

**La respuesta entera, si el usuario está escuchando.** El cierre normal dice un resumen de una frase. Con `leer on` (extensión `leer.ts` + `~/.local/state/voice/leer-respuesta.json`) la última respuesta de cada corrida se dice completa, limpia para el oído (fuera código, tablas, URLs y rutas) y troceada para empezar a sonar enseguida. Va por el daemon, así que la tecla de Windows la corta y `voice tts off` la apaga. Anuncia por el bus `voz:hablado` en `turn_end` para que el cierre no repita. Verificadores: `scripts/verify/leer-respuesta.sh` y `node --test linux/pi/agent/extensions/lib/leer.test.ts`.

**LearnHarness no trae voz: se la pone un vigía.** La app usa pi como librería (`pi-ai` + `pi-agent-core`), no el CLI, así que las extensiones de pi no corren dentro y no hay salida de voz. `linux/bin/lh-leer` (unit `lh-leer.service`) vigila el chat que la app guarda en `~/.config/LearnHarness/data/chats/*.json` —escrito al cerrar cada turno— y dice en voz alta el último mensaje NUEVO del tutor, limpio para el oído con `spoken.py` y por `voice say`. Toma línea base al arrancar (nunca lee el historial), deduplica por id (el archivo se reescribe entero) e ignora razonamiento y herramientas. Respeta `leer off` y `voice tts`. Verificador: `scripts/verify/lh-leer.sh`.

**La voz no habla encima de un dictado.** Mientras dictás, el TTS espera: el
mensaje queda en la cola y sale cuando el micrófono queda libre; si el dictado
empieza con la voz ya sonando, la corta en el acto (250 ms) y la frase vuelve a
la cola (máx. 3 reintentos). Así lo dictado nunca sale mezclado con un aviso, y
el dictado no transcribe la voz del agente. La regla vive en
`linux/voice/micguard.py`: mira el turno del dictado (`mic-busy` y
`dictate.pid`, con PID vivo y caducidad de 5 min) y, como red de seguridad, un
captura de PipeWire de Handy/Voxtype que grabe sin pasar por `handy-dictado`.
Los caminos directos del CLI (`voice repeat`, `voice inbox play`, `voice play`,
`voice history play` y la síntesis sin daemon) esperan igual. Verificador:
`scripts/verify/voz-dictado.sh`.

**Campana y "dime" (Jarvis, sin speech-to-speech).** Los mensajes de los agentes
ya no se hablan al llegar: con la entrega `bell` (por defecto) suena la campana
—una sola vez por ráfaga, nunca encima de un dictado— y el mensaje queda en el
buzón con su autor. Cuando querés, decís **"dime"** (hotword propia) o corrés
`voice dime`: **primero suena la campana** (la misma señal de "llegó algo",
ahora de "te lo leo") y después la voz lee la cola en orden,
`"<agente> dice: <mensaje>"` (texto recortado), y avisa "Quedan N mensajes más".
Si no hay nada, la hotword se calla (`--quiet-empty`).

El buzón es un **buffer acotado**, no un archivo: combina cantidad y tiempo.
Lo más viejo que `dime_max_age_min` (30 min) se descarta solo (ese ticket ya se
cerró); el buffer guarda como mucho `dime_keep` (20) y tira los más viejos; y
por lectura lee `dime_max` (6) si el backlog es viejo, o `dime_max_recent` (12)
si todo llegó hace menos de `dime_fresh_min` (15 min). Los mensajes se marcan
por `id`, no por hora: una ráfaga en el mismo milisegundo ya no se lleva de más.
Todo local (STT + TTS), nada de speech-to-speech. Verificador:
`scripts/verify/voz-dime.sh`.

**La tecla de Windows (F13).** `voice-key-listener` corre `present-remote
toggle`; una pulsación, una acción (sin antirrebote por tiempo: el de 800 ms
se comía la segunda pulsación rápida). **Si hay algo en uso, la tecla cancela
TODO** y no prende nada: audio del TTS (`voice stop`), dictado en curso
(`dictado --cancel` = descartar, no pegar) y el cartel de escritorio del aviso
que sonaba (se descarta esa notificación por el nombre del agente, no todo el
centro). Escape (`cancel_key`) cancela lo mismo, pero sólo si hay algo que cancelar.


**Registro unificado + API para cualquier proceso:** cada mensaje entregado
(voz y notificaciones) queda en `~/.local/share/voice/tts/messages.jsonl`, con
`voice messages` para verlo y `voice repeat` para releerlo. La interfaz que
usan los procesos es el CLI `voice` (no depende de Pi):

```bash
voice avisar --source Pi "texto"   # mensaje al usuario (direct/buzón/híbrido)
voice notify --app X --title T "texto"   # notifica sola
voice say "texto"                  # solo habla
voice repeat [N] | --index M       # repetir los últimos mensajes
voice inbox | play-inbox           # buzón: ver / escuchar pendientes
voice delivery [direct|mailbox|hybrid]  # inmediato, acumular o aviso+pausa+voz
```

**Entrega de mensajes:** `[tts] delivery` decide cómo entrega `avisar`:
- `direct`: habla al instante (interrumpe).
- `mailbox`: acumula en el buzón con su autor y solo suena un chime sutil; se
escuchan cuando el usuario quiere con `voice play-inbox`, que narra de quién es
cada uno y los marca escuchados. El widget de barra muestra el contador
pendiente (badge).
- `hybrid` (por defecto): suena el chime, espera `[tts] hybrid_pause` segundos
y recién habla, para que el usuario alcance a prestar atención sin distraerse.
No acumula nada en el buzón; el mensaje igual queda en el registro. Si la voz
está apagada cae al buzón para no perderlo. Mientras habla pausa la música/video
(`[tts] duck`, vía `playerctl`) para que no tape la voz, y los reanuda al terminar
(no baja el volumen del sink, así la voz no se opaca).

La voz es configurable por proceso (personalidad): `--source X` usa el perfil
`[tts.profiles.X]` de `config.toml`; si no existe, `auto_profiles = true` le
asigna una voz estable y distinta. Un perfil admite `--voice/--engine/--lang`,
`--pitch` (semitonos) y `--speed` (tempo). Se gestiona con `voice profiles`,
`voice profile show|set|remove|test|auto`. La captura automatica de notificaciones de otras apps vivia
en un hook de swaync (`linux/config/swaync/config.json` → `voice ingest-notify`);
con el shell de Omarchy ese hook ya no corre y queda pendiente. Lo que si se
registra es `voice notify` / `voice avisar`.

**Wake-word ("dime"):** `talk-command` escucha continua y dispara por palabra
clave; `dime` → `voice play-inbox`, `cuántos mensajes` → dice el conteo. El ASR
lo elige `linux/bin/voice-asr-stream` según `[wake]`: GPU si hay `gpu_command`
y AC, si no CPU (Vosk, sin VRAM). Servicio `talk-command.service` (unit en
`linux/system/systemd-user/`); se prepara con `scripts/setup-wake.sh`.

**Dictado del escritorio:** `SUPER+I` / `F7` / gesto de trackpad →
`linux/bin/dictado`. Graba con `parec`, transcribe contra `dictado.service`
(`linux/dictado/servidor.py`: faster-whisper large-v3-turbo en GPU; si no hay
VRAM libre cae a `small` en GPU y después a CPU) y escribe en la ventana
enfocada pegando por portapapeles (`wl-copy` + Ctrl+V / Ctrl+Shift+V vía
`ydotoold` o el inyector de Hyprland): byte-exacto. Tecleando con `wtype` 0.4 se
perdían o corrompían caracteres en Chromium/Electron (asigna un keycode por
carácter distinto y los keycodes 1/14/15/28/29 son Escape/Backspace/Tab/Enter/
Ctrl físicos; `atx/wtype#71`), por eso quedó sólo como último recurso y de
`DICTADO_ENTREGA=teclear`. El gesto es alterno: la primera pulsación abre la grabación,
la segunda la cierra y pega. Enter mientras dictás cierra, pega y presiona
Enter (submap `dictado`, `linux/config/hypr/dictado-submap.lua`, que replaysa
los binds globales). `SUPER+CTRL+I` abre el historial
(`linux/bin/dictado-historial` sobre `~/.local/state/dictado/historial.jsonl`).
La UI es sólo la **píldora** (`linux/config/quickshell/dictado-overlay.qml`,
servicio `dictado-overlay.service`): cápsula flotante al pie con punto rojo,
ondas que siguen tu voz y el tiempo; mientras transcribe pasa a "pensando…" y,
mientras grabás, debajo en chiquito va el micrófono que está escuchando
(descripción del source por defecto de PipeWire, la misma que abre `parec`).
Es click-through y no toma foco; lee `$XDG_RUNTIME_DIR/dictado/estado.json`,
que publica el grabador. `linux/voice/micguard.py` lee
`$XDG_RUNTIME_DIR/dictado/mic-busy` para que el TTS no hable encima del dictado. Sin palabra clave ni píldora: el dictado no depende de ningún asistente.

**Archivos:**
- `linux/voice/daemon.py` — daemon principal
- `linux/voice/chatterbox_server.py` — server persistente
- `linux/voice/engine.py` — config/estado
- `linux/home/.bashrc` — funcion `tts()`

## Zotero Read Aloud (Kokoro local)

Zotero (Firefox) toma las voces "Local" del "Read Aloud" de
**speech-dispatcher**. Un módulo genérico expone 4 voces en-US sintetizadas por
**Kokoro local** (sin cuenta ni internet): Kokoro Liam, Puck, Fable y Heart.

- `linux/voice/reader/kokoro_server.py` — daemon (modelo Kokoro en memoria).
- `linux/voice/reader/kokoro_speechd.py` — cliente que invoca speech-dispatcher:
  lee el texto de stdin, pide la síntesis y reproduce el PCM con aplay.
- `linux/bin/kokoro-server` / `kokoro-speechd` — wrappers (venv + script del repo).
- `linux/bin/kokoro-read` + `kokoro-ctl` — lector standalone de PDF/texto
  (`kokoro-read archivo.pdf`; `kokoro-ctl pausa|siguiente|anterior|salir`).
- `linux/system/speech-dispatcher/kokoro.conf` — template del módulo; el setup
  reemplaza `@HOME@` y lo instala en `/etc/speech-dispatcher/modules/kokoro.conf`.
- `linux/system/systemd-user/kokoro-tts.service` — mantiene el server vivo.
- `scripts/setup-kokoro-reader.sh` — instala todo (paquetes, venv en
  `~/.local/share/kokoro-venv`, módulo, unit) y verifica. Idempotente;
  `SKIP_KOKORO=1` lo omite en `setup-omarchy.sh`.
- `scripts/reconcile-machine.sh` — link-dotfiles + setup-kokoro-reader.
  `dotfiles-sync.sh` lo corre solo cuando cambian las entradas del reader
  (hash en `~/.local/state/dotfiles-reconcile.hash`, cooldown 30 min si falla).

**Verificación:** `spd-say -L | grep 'Kokoro Liam'`; en Zotero: Read Aloud →
Local → English (United States) → Kokoro Liam (previsualiza con ▶). Con voces
locales el resaltado es por oración (Firefox no emite eventos de palabra para
speech-dispatcher); clic en un párrafo para arrancar ahí.

**Datos de Zotero:** la biblioteca/PDFs viven en `~/Zotero` (fuera del repo);
se replican con una cuenta de Zotero (sync) o copiando el directorio.

## Handy (Speech-to-Text)

Handy es una app de speech-to-text.

**Uso:**
- `handy --start-hidden` — inicia minimizado (en autostart de Hyprland)
- `handy --toggle-post-process` — transcribe con post-procesado (keybind `F7`)
- `handy --toggle-transcription` — transcribe texto plano
- `handy — cancel` — cancela operacion actual

**Post-procesado:** provider Groq + modelo `openai/gpt-oss-120b`.

## Sunshine (Moonlight)

Sunshine = host de streaming Moonlight. Instalado en ambas maquinas.

**Gotcha importante:**
- `autoStart=false` es OBLIGATORIO. Con `Linger=yes`, graphical-session.target se activa al boot antes del login → sunshine arranca sin compositor Wayland → login colgado.
- Sunshine se arranca post-login desde `hyprland.lua`:
  `hl.exec_cmd("sleep 8 && systemctl --user start sunshine")`.

**Stream muerto = título pegado:** si se corta la conexión, Moonlight se queda en
pantalla completa con el último frame y el título `"<equipo> - Moonlight"`.
Mirar el título para decidir si hay stream deja la captura de lan-mouse
desactivada y el submap `moonlight` armado para siempre (sin mouse ni Súper).
La señal buena es el canal de control de Sunshine: `moonlight-live` mira
conexiones establecidas a los puertos 47984/47989/48010. `moonlight.lua` y
`sunshine-lan-mouse-guard` lo usan; el guard además compara el estado real de
la captura cada 30 s (sin memo) para rearmarla si algo la desactivó. En la
transición vivo→muerto, `moonlight.lua` saca de fullscreen la ventana vieja
(dispatcher `fullscreen action=unset`) para devolver el puntero relativo.

**Web UI:** `https://localhost:47990` (usuario `eztvn`, password en `~/.config/sunshine/.webui-password`).

**Pairing Moonlight (celular):**
- App Moonlight → anadir host (IP LAN o tailscale) → PIN → emparejar.
- Desktop: LAN `192.168.1.241` · tailscale `100.118.58.7`.

## Notificaciones fin de sesion (notify-sound)

`linux/config/opencode/plugins/notify-sound/plugin.js` notifica al terminar cada sesion:

1. **Campana local** (`pw-play complete.oga`) en `session.idle`.
2. **Resumen**: genera frase en espanol via Groq. Sin key → fallback "Sesion terminada".
3. **Push al celular** via ntfy.sh:
   - `session.idle` → "Sesion terminada — <resumen>" (prioridad 3)
   - `permission.updated` → "Pide permiso: <detalle>" (prioridad 4)

**Toggles** (estado local en `~/.local/state/opencode/`):

| Archivo | Valor |
|---------|-------|
| `notify-sound-enabled` | `'0'` = sin campana |
| `notify-voice-enabled` | `'1'` = hablar resumen (default apagado) |
| `notify-push-enabled` | `'0'` = sin push ntfy |

## Higiene de sueno (apagado 21:00)

Ambas maquinas se apagan solas a las 21:00 (hora Colombia).

- Timer systemd `bedtime.timer`: dispara `bedtime.service` a las **20:55** → aviso + gracia 5 min → `poweroff` a las 21:00.
- `Persistent = true`: compensa triggers perdidos.
- Escape: **`bedtime-skip`** crea flag `/run/bedtime-skip` (muere al reboot).
- Fuente de verdad: `linux/bin/bedtime.sh`.

## Modo consola (gamepad → interfaz)

Experiencia consola en PC: el gamepad controla el escritorio y la UI.

- **`input-remapper`**: daemon de sistema que re-emite teclado virtual desde pad.
- **Mapeos**: dpad → flechas, A/B → Enter/Esc, X → SUPER+SPACE, Y → SUPER+A, L = SUPER, R = SUPER+RETURN.
- **Auto modo juego**: `linux/bin/gamepad-watch.sh` detecta conexion/desconexion de pads → `game-mode.sh` / `exit`.
- **Evitar doble input**: `linux/bin/hypr-input-bridge.sh` escucha Hyprland socket y para/input-remapper segun foco.

## Privacidad de red: servicios solo por loopback + Tailscale

Los servicios que no necesitan LAN escuchan **solo en `127.0.0.1`** y se exponen
al usuario remoto por **Tailscale** (tailnet-only). Nada de `0.0.0.0` en apps sin auth.

- **`foldertinder.service`** (`~/.config/systemd/user/foldertinder.service`, puerto 8777):
  `ExecStart` con `--host 127.0.0.1` (el default del CLI en `ft/cli.py` es loopback; se deja
  explicito). `--share` en el CLI abre `0.0.0.0` a proposito: no usarlo en la unit.
  El celular entra por `https://laptopmarchy.tail77dc99.ts.net` -> `tailscale serve` (443,
  tailnet-only) proxy a `http://127.0.0.1:8777`.
- **DeepSeek Harness** (`dsh-web.service`, wrapper `linux/bin/dsh-web`): el servidor escucha en
  `127.0.0.1:3980` (fijo; si esta ocupado cae a efimero) y `tailscale serve` publica
  `https://astradeux.tail77dc99.ts.net:8446` -> `http://127.0.0.1:3980` (tailnet-only, puerto 443
  y 8443-8445 ya usados). `--serve` aplica el mapeo solo al arrancar (idempotente) y pasa
  `--trusted-host <nodo>` porque el proxy conserva el header `Host`: sin eso `/api` responde 403.
  El token es por proceso, pero el enlace de afuera es estable y la cookie de sesion dura 30 dias,
  asi que el celular escanea una vez (`dsh-web --phone` imprime el enlace + QR) y despues entra
  directo. El puerto local fijo ademas hace que la ventana y la cookie del escritorio sobrevivan
  a un reinicio del servidor. Aviso con el enlace en cada apertura (un clic lo copia). Cambiar el
  wrapper requiere `dsh-web --restart` (o el proximo arranque del servidor).
- El **Funnel `:8443` -> `127.0.0.1:3000`** es otra app (público por diseno): no tocarlo.
- Verificacion: `ss -ltn | grep 8777` = `127.0.0.1:8777`; `curl http://192.168.1.240:8777/`
  debe fallar (000) y `curl -k https://laptopmarchy.tail77dc99.ts.net/` = 200; `verify auto
  <unit>` (dominio systemd). La unit es machine-local (systemd/user), no vive en este repo.

## agentes-platform: dos enlaces tailnet (main y developing)

La app **agentes-platform** (`~/Proyectos/agentes-platform`, Next.js + pnpm) se sirve en la
maquina con **dos enlaces tailnet estables**, uno por rama, para ver en vivo lo que hacen los
agentes en cada version:

- **main**: `https://laptopmarchy.tail77dc99.ts.net:10000/` -> `127.0.0.1:3031`.
- **developing**: `https://laptopmarchy.tail77dc99.ts.net:10001/` -> `127.0.0.1:3040`.

Ambos solo-tailnet (`tailscale serve`), loopback `127.0.0.1` en la maquina (nada de `0.0.0.0`).

- **Units** (`linux/system/systemd-user/`, instaladas por `setup-omarchy.sh`):
  `agentes-platform-main.service` y `agentes-platform-developing.service`, `Restart=always`,
  `StartLimitBurst=20`. Dueñas del ciclo de vida: no lanzar `next` a mano para estos puertos.
- **Wrapper**: `linux/bin/agentes-platform-serve <main|developing>` (symlink en `~/.local/bin/`).
  `main` construye si el build esta obsoleto (`find ... -newer .next/BUILD_ID`) y corre
  `next start`; `developing` corre `next dev` sobre el worktree persistente
  `~/Proyectos/.rig-worktrees/agentes-platform/developing` (siempre refleja el codigo actual).
- **Los dos modos difieren a proposito**: Next 16 admite **un solo `next dev` por arbol** (el
  segundo falla con "Another next dev server is already running"). El usuario tiene su dev en
  `:3020` sobre el arbol main, asi que main se sirve con **build de produccion + `next start`**
  (convive con el dev, que vive en `.next/dev/`). El worktree `developing` es dedicado -> ahi si
  `next dev`. `next.config.ts` ya declara `allowedDevOrigins` con el host tailnet.
- **`.env.local`**: el wrapper enlaza `Proyectos/.env.local` -> `main/.env.local` si falta (el
  archivo es gitignored y no viaja con el worktree).
- **Puertos reservados**: NO reusar `38000` (`PREVIEW-SEGURO`) ni `47000`; los enlaces de
  agentes-platform son `10000 -> 3031` y `10001 -> 3040`. Un puerto nuevo = un enlace nuevo.
- **Verificacion**: `systemctl --user is-enabled agentes-platform-main.service
  agentes-platform-developing.service` = enabled; `is-active` = active;
  `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3031/` = 200 y
  `http://127.0.0.1:3040/` = 200; `curl ... https://laptopmarchy.tail77dc99.ts.net:10000/` = 200
  y `:10001/` = 200; `ss -ltn | grep -E '3031|3040'` = `127.0.0.1`. `verify auto
  linux/system/systemd-user/agentes-platform-*.service` (dominio systemd).

## Lo que NO se gestiona

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes.

## Autonomia de ejecucion

Cuando modifiques archivos de configuracion relacionados con Linux (Hyprland, Waybar, Hyprpaper, PipeWire, systemd, keyd, GTK, Qt, shell, etc.), no te detengas despues de editar.

Despues de cada modificacion:

1. Ejecuta automaticamente todos los comandos necesarios para aplicar los cambios.
2. Verifica que los cambios se hayan aplicado correctamente.
3. Si aparece un error, investiga la causa e intenta solucionarlo.
4. Repite el ciclo de editar → aplicar → verificar hasta que el problema quede resuelto.

Solo solicita confirmacion para operaciones potencialmente destructivas:
- Eliminar archivos o directorios.
- Reinstalar o desinstalar paquetes.
- Sobrescribir datos importantes.
- Reiniciar o apagar el sistema.

Los reinicios de aplicaciones, recargas de servicios, validaciones de configuracion y operaciones rutinarias **no requieren confirmacion**.

## Puente Discord <-> `main` (hablarle desde el celular)

El dueno habla con su agente primario `main` desde un **canal dedicado de Discord**: ahi vive el
agente, ahi le escribe. Transporte elegido por el usuario (Telegram queda como alternativa
documentada; WhatsApp documentado). Detalle completo en `docs/main-bridge.md`.

- **Entrada**: `rig-discord-bot` recibe el mensaje del canal por el Gateway de Discord, valida
  que el autor este en la allowlist de **user ids** y lo inyecta en la silla con
  `rig send main-seat "[dc] <texto>"`.
- **Salida**: `main` responde con `rig say "<respuesta>"` (evento `kind=reply`, `actor=main`);
  el bot sigue `~/.local/state/rig/events.jsonl` y reenvia los replies al canal dedicado.
- **Hilos por pedido (conversacion matricial)**: cada pedido nuevo del usuario abre un **hilo
  nativo de Discord** (nombre = numero/titulo del ticket o las primeras palabras de la idea);
  el canal general queda limpio y el detalle vive en el hilo. `main` responde **una vez** por
  mensaje del usuario, corto; prohibido encadenar varios mensajes largos en el canal (el reporte
  largo se parte **dentro** del hilo, tope 2000 chars por mensaje). Se usa la **respuesta nativa**
  de Discord (`message_reference`) para saber a que mensaje contesta el usuario. **Limite
  honesto**: Discord da un solo nivel de hilo (no hay arbol infinito tipo Reddit): hilo por
  pedido + respuestas con cita al padre; un arbol profundo lo dibuja la interfaz del hub, no
  Discord. Toggle `RIG_DISCORD_THREADS` (default 1).
- **Registro padre/hijo (para el hub)**: cada mensaje emitido deja un evento con el id propio y
  el del padre. Forma canonica (acordada con `work-hub-conversacion`): `kind` en `{conv-in,
  conv-out, ask, answer}`, `data={channel_id, thread_id, message_id, parent_id, child_id, to}`;
  el hub enlaza por `parent_id` y el rol sale de `actor` (usuario -> user, main/bot -> assistant).
- **Extraccion conversacional (adjuntos)**: se pide conversando ("bajame la conversacion y el
  pensamiento del ticket 93"); el bot detecta verbo de entrega + sustantivo de contenido, saca el
  ticket (`#93` o `FOO-3`) y sube el archivo (`extraccion-<ticket>.md`) como adjunto dentro del
  hilo con `Sesion: <ticket> · generado: <hora ISO>`. El bot invoca la extraccion (env
  `RIG_EXTRACT_CMD`, default `rig export`) con la *cosa* (ticket/silla/sesion) y sube el archivo
  que `rig export` imprime en stdout (owner `work-visibilidad-y-cierre`; tambien `rig ticket
  show <id>`); **no** lee la base de opencode por su cuenta.
- **`main` en silla**: `main` corre como silla tmux (`rig spawn main-seat --agent main`) para
  ser direccionable; el pane de herdr le hace attach para seguir viendolo en el escritorio.
  La unidad `rig-main-seat.service` la mantiene viva (la levanta al iniciar sesion y la
  repone si muere) y `tmux-reap.sh` la exime del reaper. El keepers tambien cubre el server
  **wedgeado** de tmux (colgado sin atender el socket, kitty shell=tmux sin terminal:
  caida de terminales del 2026-10-30): `rig-seat-keep` llama a tmux con timeout y, si no
  responde, mata el server con SIGKILL y lo deja revivir en la siguiente vuelta (aviso de
  escritorio con cooldown): ver `ALIVE_TIMEOUT`/`SPAWN_TIMEOUT` en `linux/bin/rig-seat-keep`.
- **Sin puertos**: el bot abre conexion **saliente** al Gateway (`wss://gateway.discord.gg`);
  nada escucha en la LAN/internet. Bot Python3 stdlib (WebSocket propio), sin `discord.js`.
- **Seguridad**: allowlist estricta de **user id**; token, allowlist y `channel_id` en
  `~/.config/rig/discord.env` (chmod 600, FUERA del repo); se ignora todo mensaje de bots u
  otros canales; cada mensaje queda como evento (`discord-in/out/voice/error/reject`).
- **Alta del bot**: el usuario debe crear/reusar la app en el portal de Discord, activar
  **MESSAGE CONTENT INTENT**, regenerar el token e invitar el bot con permisos `76800` (View
  Channel + Send Messages + Read Message History); luego pega el token/user id/channel id en
  `~/.config/rig/discord.env`. Paso a paso en `docs/main-bridge.md`.
- **Regla para `main`**: un mensaje que empieza con `[dc]` se responde al usuario con
  `rig say "<respuesta>"`; un mensaje `[app] t=<hilo> <texto>` (Hilos de agentes-platform)
  se responde con `rig say "<respuesta>" --to app --thread <hilo>` y la app lo muestra en
  ese hilo.
- **Escalado al humano (bidireccional)**: el canal tambien sirve para que **cualquier flujo que
  se trabe llame al usuario**. La silla pregunta con
  `rig-escalate "<pregunta>" --ticket X --seat S --priority alta|normal` (o `rig ask`, subcomando
  que integra `work-rig-reconcile` como wrapper delgado del script; este ticket NO edita `rig`).
  El script: (1) emite `kind=ask` (`data.awaiting`) en el registro; (2) marca el ticket `blocked`
  con motivo; (3) avisa por escritorio (`notify`) y por voz (TTS `voice`); (4) el bot de
  Discord publica la pregunta con **mencion** `<@user_id>` (dispara push del telefono). El retorno
  es el punto clave: la respuesta del usuario (texto o nota de voz) viaja de vuelta a la silla
  que pregunto (`rig send <seat> "[dc] [respuesta] ..."`), la **desbloquea** (`rig ticket set
  --status in-progress`) y queda como evento `kind=answer`; la cola vive en
  `pending-asks.json` (LIFO). Con una pregunta pendiente, el texto del canal se trata como
  respuesta (prefijo `!` para hablarle a `main` igual).
- **Urgencia/reintento**: si un `ask` sigue sin respuesta mas de `RIG_DISCORD_ESCALATE_MIN`
  minutos (default 10), el bot republica con mencion + re-dispara escritorio/voz
  (`rig-escalate --remind`) y emite `kind=ask-reminder`.
- **Marca de tiempo y fuente (regla)**: todo mensaje que el puente publica en el canal expone su
  hora y su origen. El ask cierra con `-# <hora ISO> · fuente <actor|seat>`; las respuestas de
  `main` salen con `-# <hora ISO> · main`. Las horas son las del evento (`ts`). El reporte del
  punto de entrada se reconstruye en el momento citando hora y fuente, sin mirar el reloj a ojo.
- **Aviso al telefono (opciones, documentadas)**: la mencíon/DM de Discord disparan el push de su
  app; el `ntfy` local ya existe. Una **llamada telefonica real** requiere proveedor externo
  (Twilio/Vonage) con costo por minuto y numero; un bot de Discord **no** puede iniciar llamada
  de voz ni timbre. Sin implementar telefonia (ver `docs/main-bridge.md`, tabla de costos/fases).
- **Unit**: `linux/system/systemd-user/rig-discord-bot.service` (`Restart=always`,
  `EnvironmentFile`, `ConditionPathExists=%h/.config/rig/discord.env`; sin token queda
  `condition failed`, no arranca).
- **Voz**: nota de voz de Discord (attachment `audio/*`) -> STT local (aun no instalado) ->
  texto; respuesta en audio via `voice` (chatterbox). Llamada telefonica real (SIP) NO viable
  sin proveedor externo; canales de voz nativos de Discord fuera de alcance. WhatsApp: solo
  documentado (Cloud API oficial vs no-oficial con riesgo de bloqueo del numero).
- **Un solo transporte**: NO correr el bot de Telegram y el de Discord a la vez (ambos reenvian
  los mismos `kind=reply`).
- Dueño: `supervisor` (doctrina/canal) + `dotfiles` (script y unit).
  Verificacion: `verify run bridge` (py_compile + selftest + token-leak + unit + symlink, para
  discord y telegram) y `verify run rig`. Config nueva -> reinicia opencode no aplica; la silla
  `main-seat` la mantiene `rig-main-seat.service` (manual: `rig spawn main-seat --agent main`).
