# dotfiles

Configuraciones personales gestionadas desde este repositorio como fuente de verdad.

## Estructura

```
linux/      → Configuraciones para Linux (Hyprland, Waybar, Kitty, etc.)
common/    → Configuraciones multiplataforma (futuro)
windows/   → Futuro
macos/     → Futuro
scripts/   → install.sh, publish.sh
docs/      → Documentacion
```

## Uso

```bash
# Instalar enlaces simbolicos
~/dotfiles/scripts/install.sh

# Modo no interactivo (idempotente)
~/dotfiles/scripts/install.sh --force

# Publicar cambios
~/dotfiles/scripts/publish.sh
```

**Importante:** editar siempre dentro de `~/dotfiles/`, nunca en `~/.config/`. Ver `AGENTS.md`.