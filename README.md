# dotfiles

Configuraciones personales gestionadas desde este repositorio como fuente de verdad.

## Estructura

```
linux/     → Configuraciones para Linux (Hyprland, Waybar, Kitty, etc.)
common/   → Configuraciones multiplataforma (futuro)
windows/  → Futuro
macos/    → Futuro
scripts/  → Scripts auxiliares
docs/     → Documentación
```

## Uso

```bash
# Instalar enlaces simbólicos
~/dotfiles/install.sh

# Publicar cambios
~/dotfiles/publish.sh
```

**Importante:** editar siempre dentro de `~/dotfiles/`, nunca en `~/.config/`. Ver `AGENTS.md`.