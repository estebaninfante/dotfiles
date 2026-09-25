---
name: quickshell
description: >
  DEPRECATED. Apunta al shell viejo de dotfiles (`~/.config/quickshell/`), que NO
  es la barra activa. Usa el agente `omarchy-shell` para la barra/shell de Omarchy.
mode: subagent
model: anthropic/claude-sonnet-4-6
permission:
  bash: allow
  edit: allow
  read: allow
---

DEPRECATED — NO EDITES QML DESDE ESTE AGENTE.

La barra activa de esta maquina es el shell de **Omarchy** (Quickshell), no el de
dotfiles. Este agente describe `~/.config/quickshell/`, que ya no se usa.

Redirige todo a:

- Agente global: **`omarchy-shell`** (`~/.config/opencode/agents/omarchy-shell.md`).
- Config activa: `~/.config/omarchy/shell.json` y `~/.config/omarchy/plugins/`.
- FUENTE del paquete (solo lectura): `/usr/share/omarchy/shell/`.

Si te invocan para cambios de barra/OS: no toques nada, responde que se use el
agente `omarchy-shell` (o cárgalo desde el hilo principal).
