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
  paquete; se sobrescribe en updates). Se lanza con `omarchy-launch-shell` y se configura
  desde `~/.config/omarchy/shell.json` (+ plugins en `~/.config/omarchy/plugins/`).
  Ver el skill `omarchy` (plugins.md) antes de tocarla.
- **NO USAR**: `~/.config/quickshell/` (symlink a los dotfiles). Aunque tenga su propio
  AGENTS.md, NO es la barra activa; no editarla para cambios de UI/barra salvo que el
  usuario lo pida explicitamente.

Regla: ante cualquier pedido sobre "mi barra" / shell, aplicar SIEMPRE en Omarchy.

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
| Meta: agentes / eficiencia | `supervisor` | auditar agentes, plugins, skills, sesiones, fallbacks de modelo, loops |
| Dotfiles / maquina | `dotfiles` | repo `~/dotfiles/`, symlinks, setup, scripts |
| Computer use | `computer-use` | automatizacion de GUI/escritorio |

Si un pedido toca un dominio **sin owner**, eso es un hueco: crea el owner antes de tocar
nada (ver regla meta).

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

## Verificacion (skill `verification`)

Verificar SIEMPRE con el sistema determinista, no a ojo ni razonando. Skill
`~/.config/opencode/skills/verification/`; atajo `verify` (`~/.local/bin/verify`).

- Tras editar: `verify auto <archivo...>` (exit 0 PASS / 1 FAIL / 2 ERROR). `--quiet`
  solo imprime fallos; `--activate` permite efectos (restart shell, hyprctl reload).
- Dominios: `quickshell`, `hyprland`, `systemd`, `code`, `syntax`. Ver `verify list`.
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

