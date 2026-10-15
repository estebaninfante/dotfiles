---
name: dotfiles-publish
description: Publica y sincroniza el repo ~/dotfiles para que el cambio quede en el remoto y en la otra máquina, incluso si está incompleto. Usar SIEMPRE después de tocar cualquier archivo versionado (config symlinkeada como hypr/kitty/nvim/swaync, o la config viva de Omarchy en ~/.config/omarchy, o scripts en linux/bin). También cuando el usuario diga "subí esto", "sincronizá", "guardá los cambios", "que quede en el otro equipo".
---

# dotfiles-publish

El repo `~/dotfiles` es la única fuente de verdad. La config viva de Omarchy
(`~/.config/omarchy/`) es copia, no symlink, así que hay que exportarla. Este
repo se sincroniza entre laptop y desktop.

## Regla

Después de **cualquier** cambio versionado, publicar:

```bash
~/dotfiles/scripts/dotfiles-sync.sh --force
```

Eso hace, en orden:

1. `export` de `~/.config/omarchy` → repo (aditivo, nunca borra).
2. `git add -A` + commit automático (`autosync(<host>): <fecha>`), aunque esté a medias.
3. `git pull --rebase=merges --autostash` (integra lo del otro equipo).
4. Si vino shell del otro equipo, `import` a la config viva.
5. `git push`.

Si hay conflicto de rebase, avisa y no importa. Resolver a mano:
`cd ~/dotfiles && git pull --rebase=merges`.

## Antes de publicar

- No commitear secretos: viven en `~/.config/dotfiles-secrets.sh` (fuera del
  repo) o están en `.gitignore` (`linux/config/opencode/secrets/`, `gh/hosts.yml`).
- Para cambios de config symlinkeada (hypr, kitty, nvim, swaync, tmux, opencode,
  quickshell) alcanza con editar `~/dotfiles/linux/config/...`; el commit los toma.
- Para scripts propios, van en `linux/bin/` (el inventario de
  `scripts/link-dotfiles.sh` los enlaza a `~/.local/bin`).

## Verificar

```bash
~/dotfiles/scripts/omarchy-sync.sh status   # DRIFT si lo vivo difiere del repo
git -C ~/dotfiles status                    # limpio tras publicar
```

Para pausar el timer: crear `~/.config/dotfiles-autosync.off` (o menú de la
barra: Dotfiles > Auto-sync).
