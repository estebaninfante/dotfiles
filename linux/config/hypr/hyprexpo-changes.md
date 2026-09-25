# Hyprexpo — registro de cambios

Config del overview/grilla de workspaces (`SUPER + Y`). Todo vive en
`~/.config/hypr/hyprland.lua`, bloque **HYPREXPO** (aprox. lineas 390–446).

- Plugin: `hyprexpo` (cargado desde `/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so`
  via `hl.plugin.load(...)` en linea 397).
- Grilla fija 3x3 (`columns = 3`, `rows = 3`), orden numpad `789 / 456 / 123`
  (`reverse_rows = 1`, parche local).
- Estilo editable en la tabla `expo_style` (linea 406). Colores salen del tema
  Omarchy activo via `theme_color(...)`.
- Recarga: `hyprctl reload` (auto-reload al guardar, pero validar).

## Cambio 2026-09-24 — quitar borde y etiquetas (grilla mas "un solo wallpaper")

Motivo: al abrir el overview se percibia separacion entre tiles. El wallpaper
generado es 100% seamless (verificado con zoom sobre la costura); la separacion
venia del `border_width` de hyprexpo, no de la imagen.

| Clave | Antes | Despues |
|-------|-------|---------|
| `expo_style.border_width` (linea 409) | `2` | `0` |
| `label_enable` (linea 436) | `1` | `0` |
| `show_workspace_numbers` (linea 437) | `1` | `0` |

Estado: aplicado con `hyprctl reload` → ok, `hyprctl configerrors` → vacio.

### Revertir
Restaurar el backup **previo a este cambio** (tiene `border_width = 2` y
labels en 1):

```
cp ~/.config/hypr/hyprland.lua.bak.1790228045 ~/.config/hypr/hyprland.lua
hyprctl reload && hyprctl configerrors
```

O editar a mano: linea 409 `border_width = 2`, lineas 436–437 volver a `1`.

## Cambio 2026-09-24 — fondo compartido (tiles transparentes)

Motivo real de la "separacion": cada tile era un screenshot completo del
workspace (incluia el wallpaper), asi que la grilla mostraba n mini-wallpapers.
La imagen seamless no bastaba.

Ahora los tiles se capturan **transparentes** (solo ventanas + bordes) y el
fondo continuo lo dibuja el overview con `expo_style.background_image` a pantalla
completa. Al abrir la grilla el wallpaper NO se divide.

Implementado en el fork local (`~/dotfiles/linux/patches/hyprexpo-local.patch`),
parche que se aplica con `~/dotfiles/linux/bin/hyprexpo-rebuild.sh`:

- Nuevo flag `plugin:hyprexpo:tile_transparent` (**default 1 = ON**). Poner `0`
  para volver al comportamiento anterior (wallpaper repetido por tile).
- En `captureWorkspacePreview`: FB a transparente, se detachan las layer
  surfaces `BACKGROUND` (hyprpaper + omarchy-background) y `TOP` (omarchy-bar),
  y se neutraliza el clear opaco de `renderBackground` + splash durante el render.

- Requiere **reiniciar Hyprland** (logout/login): `hyprctl reload` NO recarga el
  `.so`. Ya instalado en `/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so`.
- Notas: la barra omarchy y el overlay "LAN Mouse Sharing" no aparecen en los
  tiles. El blur de ventanas puede samplear el FB transparente (halo leve).

### Revertir solo esta funcion
Agregar en el bloque hyprexpo de `hyprland.lua`: `tile_transparent = 0`, luego
`hyprctl reload`. (Requiere que el `.so` nuevo ya este cargado.)

## Backups (en este mismo directorio)

- `hyprland.lua.bak.1790228045` — estado **antes** del cambio de hyprexpo
  (border_width=2, labels on). Usar para revertir.
- `hyprland.lua.bak.1790225169` — backup anterior (23:46), mas viejo, con otros
  cambios previos (theme_color helper, gaps dinamicos).

## Notas

- Este directorio es symlink a `~/dotfiles/linux/config/hypr/`, asi que el cambio
  esta versionado en git dentro del repo `dotfiles`.
- `omarchy refresh hyprland` sobrescribe el archivo; los backups de arriba son el
  respaldo si eso pasa.
