# linux/bin

Scripts propios del usuario, enlazados a `~/.local/bin/` por `scripts/link-dotfiles.sh`.

## `rig` — sillas tmux + tablero de tickets

`rig` orquesta agentes de opencode en sillas tmux (una sesion = una terminal = un agente
top-level), un store de tickets en vivo y su render. bash + tmux + jq (+ sqlite3 opcional).

### Sillas

- `rig seats [--porcelain]` — lista sillas (sesiones tmux marcadas `@agent 1`).
- `rig spawn <nombre> [--agent A] [--cwd DIR] ...` — crea la silla corriendo opencode.
- `rig send <silla> [--force] "..."` — inyecta texto + Enter (bracket-paste si multilinea).
- `rig read <silla> [--lines N]` — captura el output reciente.
- `rig whoami` — silla actual (dentro de tmux).

### Tickets (store: `~/.config/opencode/tickets.json`)

- `rig ticket add <id> --project P --title T [--status S] [--owner O] [--evidence E]
  [--session SES] [--area A]`
- `rig ticket list [--project P] [--status S] [--area A] [--porcelain]`
- `rig ticket set <id> [--status --owner --evidence --title --project --session --area]`
- `rig ticket done <id> [--close-seat]` · `rig ticket rm <id>`
- `rig ticket metrics [<id>...] [--project P] [--status S] [--porcelain]`
- `rig ticket backfill` — rellena `area` por prefijo/proyecto y asigna `num` (migracion).
- `rig ticket set|done|rm|metrics <ref>` — `<ref>` es el slug (`id`) o el numero (`#12` o `12`).
- `rig board [--watch] [--porcelain] [--plain] [--no-metrics] [--area A] [--project P]
  [--status S] [--interval SEG]`

Estados: `pending | in-progress | blocked | done`.

### Numero y titulo

- `num`: entero secuencial por orden de creacion (1, 2, 3...), asignado por `rig ticket add` y
  por `rig ticket backfill` en la migracion. Se muestra como prefijo `#12` en `rig board` y
  `rig ticket list`. El slug sigue siendo el `id` interno (branch/worktree no cambian).
- Titulo: `rig ticket add` exige >= 6 palabras, en espanol, descriptivo (no un slug). El slug
  identifica; el titulo explica.

### Areas (agrupacion + color)

Campo opcional `area` por ticket; es el eje de agrupacion de `rig board` y su filtro.

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

- `--area A` filtra (`--area none` = sin area). Backfill: HR* -> hr, HYPR* -> hypr,
  FT-* -> foldertinder, M-*/META-*/WEB-RESEARCH -> meta, resto por proyecto.
- `rig board` agrupa por area con cabecera coloreada y prefija cada fila con `#num`; columnas de
  ancho fijo (el titulo se trunca al ancho de la terminal: sin desbordes). `--plain` = plano, sin
  color ni agrupacion (para pipes). `--porcelain` (JSON) y `rig ticket list --porcelain` exponen
  `area` + `color` + `num` por ticket (contrato que consumen `agentes-platform` y la silla de
  trazabilidad).

Estados y forma del store, worktrees y metricas: ver el `AGENTS.md` de `~/.config/opencode/`
(seccion "Tablero de tickets en vivo"). Verificacion: `verify run rig` + `rig --selftest`.
