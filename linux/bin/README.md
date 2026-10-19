# linux/bin

Scripts propios del usuario, enlazados a `~/.local/bin/` por `scripts/link-dotfiles.sh`.

## `agent-os-cli` — observar agentes (sillas tmux, tickets, sesiones)

> Antes se llamaba `rig`. El alias `rig` sigue existiendo pero se va a quitar.

`agent-os-cli` orquesta agentes de opencode en sillas tmux (una sesion = una terminal = un agente
top-level), un store de tickets en vivo y su render. bash + tmux + jq (+ sqlite3 opcional).

### Sillas

- `agent-os-cli seats [--porcelain]` — lista sillas (sesiones tmux marcadas `@agent 1`).
- `agent-os-cli vivos [--porcelain]` — **agentes vivos** en cualquier panel tmux: nombre, rol, color,
  ticket actual y ticket raíz. Avisa (y sale 1) si dos vivos comparten color.
- `agent-os-cli colores` — verifica que no haya colores repetidos entre agentes vivos.
- `agent-os-cli spawn <nombre> [--agent A] [--cwd DIR] ...` — crea la silla corriendo opencode.
  Si `--ticket ID` ya lo trabaja otra silla viva, se niega: **un ticket = un agente**.
- `agent-os-cli send <silla> [--force] "..."` — inyecta texto + Enter (bracket-paste si multilinea).
- `agent-os-cli read <silla> [--lines N]` — captura el output reciente.
- `agent-os-cli whoami` — silla actual (dentro de tmux).

### Tickets (store: `~/.config/opencode/tickets.json`)

- `agent-os-cli ticket add <id> --project P --title T [--status S] [--owner O] [--evidence E]
  [--session SES] [--area A]`
- `agent-os-cli ticket list [--project P] [--status S] [--area A] [--porcelain]`
- `agent-os-cli ticket set <id> [--status --owner --evidence --title --project --session --area]`
- `agent-os-cli ticket done <id> [--close-seat]` · `agent-os-cli ticket rm <id>`
- `agent-os-cli ticket metrics [<id>...] [--project P] [--status S] [--porcelain]`
- `agent-os-cli ticket backfill` — rellena `area` por prefijo/proyecto y asigna `num` (migracion).
- `agent-os-cli ticket set|done|rm|metrics <ref>` — `<ref>` es el slug (`id`) o el numero (`#12` o `12`).
- `agent-os-cli board [--watch] [--porcelain] [--plain] [--no-metrics] [--area A] [--project P]
  [--status S] [--interval SEG]`

Estados: `pending | in-progress | blocked | done`.

### Numero y titulo

- `num`: entero secuencial por orden de creacion (1, 2, 3...), asignado por `agent-os-cli ticket add` y
  por `agent-os-cli ticket backfill` en la migracion. Se muestra como prefijo `#12` en `agent-os-cli board` y
  `agent-os-cli ticket list`. El slug sigue siendo el `id` interno (branch/worktree no cambian).
- Titulo: `agent-os-cli ticket add` exige >= 6 palabras, en espanol, descriptivo (no un slug). El slug
  identifica; el titulo explica.

### Areas (agrupacion + color)

Campo opcional `area` por ticket; es el eje de agrupacion de `agent-os-cli board` y su filtro.

| area | dominio | color |
|------|---------|-------|
| `hr` | hypr-remote | `#4C9AFF` |
| `hypr` | hyprland / plugins | `#B389FF` |
| `shell` | omarchy-shell / QML | `#FFB84C` |
| `audio` | PipeWire / WirePlumber | `#4CD9A0` |
| `meta` | agent-os-cli / agentes / herdr / doctrina | `#8A8F98` |
| `infra` | dotfiles / systemd / packages | `#FF7A85` |
| `foldertinder` | foldertinder | `#7ADBFF` |
| (sin area) | — | `#8A8F98` |

- `--area A` filtra (`--area none` = sin area). Backfill: HR* -> hr, HYPR* -> hypr,
  FT-* -> foldertinder, M-*/META-*/WEB-RESEARCH -> meta, resto por proyecto.
- `agent-os-cli board` agrupa por area con cabecera coloreada y prefija cada fila con `#num`; columnas de
  ancho fijo (el titulo se trunca al ancho de la terminal: sin desbordes). `--plain` = plano, sin
  color ni agrupacion (para pipes). `--porcelain` (JSON) y `agent-os-cli ticket list --porcelain` exponen
  `area` + `color` + `num` por ticket (contrato que consumen `agentes-platform` y la silla de
  trazabilidad).

Estados y forma del store, worktrees y metricas: ver el `AGENTS.md` de `~/.config/opencode/`
(seccion "Tablero de tickets en vivo"). Verificacion: `verify run agent-os-cli` + `agent-os-cli --selftest`.

## Agentes pi: un color por vivo, un ticket por agente

La extensión `linux/pi/agent/extensions/agent-os-cli.ts` captura solo el árbol de trabajo:

- Cada sesión de pi abre un **ticket raíz** (`tipo: sesion`): el agente vivo.
- Cada pedido del usuario abre un **subticket** con su propio trace.
- Cada delegación (`subagent`) abre un **subticket hijo**; el proceso hijo cuelga su
  trabajo de esa delegación y nunca crea otra raíz ni toca el panel del padre.
- Todo se ve con `/tareas`, `/tarea T-XXXXXX`, `/traza` y `/trazas`, y además queda en
  Markdown legible: `~/.local/share/pi/trazas/<ticket-raíz>.md` + `index.md`.
  Desde la terminal: `agent-os-cli trazas` (índice) y `agent-os-cli traza T-XXXXXX` (traza completa).
- Un ticket pertenece a una sola sesión (`dueno`): otro agente solo lo lee y crea uno nuevo.

Los colores salen de `linux/voice/identity.py`. Al arrancar, cada agente **reclama** un
color libre entre los vivos (`voice identity --claim`); si otro agente ya lo tiene, toma
el siguiente y lo guarda. En cada turno, `conversar.ts` revisa si quedó un color repetido
y lo corrige sin reiniciar. Verificación: `scripts/verify/agentes.sh`, `agent-os-cli colores`,
`agent-os-cli vivos`.
