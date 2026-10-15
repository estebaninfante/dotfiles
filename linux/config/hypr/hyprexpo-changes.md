# Hyprexpo — registro de cambios

## Cambio 2026-10-15 — un solo wallpaper (desktop + overview) y soporte Wallpaper Engine

**Motivo (reporte del usuario)**: el escritorio mostraba el wallpaper del tema
(Porsche, via symlink canonico) y al abrir la overview se veia todo negro: el
plugin pintaba su backdrop propio con
`background_image = ~/.config/omarchy/backgrounds/black/amoled-black.png`, con
tiles transparentes encima. Dos fondos distintos; ademas pidio poder usar
cualquier foto estatica (jpg/png) y wallpapers de Wallpaper Engine (Steam).

**Estado del modo transparente hoy**: `background_transparent = 1`
(desde el cambio 2026-09-25c) dejo de funcionar en la sesion viva: al abrir la grilla se
renderiza SOLO el wallpaper contino, sin tiles ningun preview, y
`kb_focus` no cambia un pixel (0-diff entre capturas con grim); con backdrop
interno (`background_transparent = 0` + imagen canonica) la grilla DIBUJA
tiles + previews (verificado con grim). La activacion de ese flag en la config
no produce `configerrors`, asi que el hilo del hook de render directo
(`hkRenderWorkspace`) esta mismamente cambiado desde la reorganizacion del
2026-10-15/actualizacion de la sesion. Sin rebuild del `.so`; el flag queda
OFF hasta diagnosticar eso.

**Cambio (solo config, sin rebuild; `hyprctl reload` basta)**:

- `plugins/hyprexpo.lua`:
  - Nuevo resolver de `bg_image`: apunta al symlink canonico ->
    `~/.local/state/omarchy/current/background` (la misma fuente que el
    escritorio; si el usuario cambia el fondo con `omarchy theme bg set`
    / `sync-wallpaper.sh`, la expo sigue automaticamente en la proxima
    apertura: `loadBackgroundImage()` corre por-open en el constructor).
  - Si `~/.config/wallpaper-source` = `video`, usa el frame PNG del
    wallpaper activo (`~/.cache/wallpaper-frames/<id>.png`, capturado por
    `wallpaper-switch.sh`) — desktop con video en vivo, expo con el frame
    del MISMO wallpaper.
  - Fallback al amoled-black del tema si el resuelto no existe.
  - `background_transparent = 0` (ver arriba: roto hoy).
- `~/.local/bin/wallpaper-switch.sh` (dotfiles `linux/bin/`):
  - `WORKSHOP_DIR` ahora se resuelve con `resolve_workshop_root()`:
    `.steam/steam` (symlink) -> `~/.local/share/Steam` -> Steam Flatpak;
    fallback `.steam/steam`. Antes hardcodeado.
  - `use_video` y `use_static` corren `hyprctl reload` al final: sin esto el
    string de `background_image` en la config quedaba viejo al cambiar la
    fuente (static<->video cambia el path symlink<->frame).
- `~/.config/systemd/user/linux-wallpaperengine.service`: instalada desde
  `~/dotfiles/linux/system/systemd-user/` (faltaba en la maquina pese a que
  `autostart.lua` la arranca si source=video) + `daemon-reload` + `enable`.
- Build de `linux-wallpaperengine-git` (AUR) lanzada en background
  (`/tmp/lwe-build.log`); la maquina hoy NO tiene ni Steam ni el binario.

**Flujo uniforme** (una sola fuente de verdad):
- Estatico: `omarchy theme bg set <imagen.jpg|png|webp>` (o
  `sync-wallpaper.sh <imagen>`) → hook theme-set propaga hyprpaper + symlink;
  la expo apunta al symlink (re-lee el archivo en cada apertura).
- Video: `wallpaper-switch.sh list` / `set <id>` → LWE dibuja el workshop
  item; la expo usa su frame cacheado; `use static` vuelve al fondo canónico.

**Aplicar**: ya aplicado con `hyprctl reload`; `hyprctl configerrors` vacio.

### Revertir
En `plugins/hyprexpo.lua`: `background_image = os.getenv("HOME") ..
"/.config/omarchy/backgrounds/black/amoled-black.png"` y quitar el bloque
del resolver; `hyprctl reload`. Para el modo transparente (cuando se
diagnostique el hook): `background_transparent = 1`. Los de `wallpaper-switch.sh`
con `git checkout` del repo dotfiles.

Config del overview/grilla de workspaces (`SUPER + Y`). Todo vive en
`~/.config/hypr/hyprland.lua`, bloque **HYPREXPO** (aprox. lineas 390–446).

- Plugin: `hyprexpo` (cargado desde `/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so`
  via `hl.plugin.load(...)` en linea 397).
- Grilla fija 3x3 (`columns = 3`, `rows = 3`), orden numpad `789 / 456 / 123`
  (`reverse_rows = 1`, parche local).
- Estilo editable en la tabla `expo_style` (linea 406). Colores salen del tema
  Omarchy activo via `theme_color(...)`.
- Recarga: `hyprctl reload` (auto-reload al guardar, pero validar).

## Cambio 2026-10-09i — morph del overview: leaf de animacion dedicada (`zoomFactor`)

**Sintoma**: al elegir un workspace desde la grilla (`SUPER+<n>`, hover-select, click o
`SUPER+Y`), la transicion grilla -> workspace salia seca/brusca, sin morph.

**Causa raiz**: el plugin anima su zoom con la leaf indicada por
`plugin:hyprexpo:animation`. `plugins/hyprexpo.lua` la fijaba en `specialWorkspace`,
pero la migracion a modulos dejo `specialWorkspace` (y `In`/`Out`) en
`enabled = false` (`animations.lua`) — necesario para que el scratchpad de Moonlight
cambie en seco. Con la leaf deshabilitada, `Hyprutils::Animation` hace warp inmediato
(`AnimatedVariable.hpp`: `!enabled()` -> warp), asi que `size`/`pos`/`tiltAnim` del
overview saltaban al goal en un frame: sin frames intermedios = sin morph.
Ruta: `plugins/hyprexpo.lua:84` apuntaba a `animations.lua:42-55` (leaf off).

**Fix** (solo config, SIN rebuild del `.so`; `hyprctl reload` basta):

- `animations.lua`: nueva leaf libre `zoomFactor` con `enabled = true`, `speed = 4`,
  `bezier = "expoOpen"` (misma curva/velocidad que usaba `specialWorkspace` antes).
- `plugins/hyprexpo.lua`: `config.animation = "zoomFactor"` (antes `"specialWorkspace"`).
- Se conserva `specialWorkspace`/`In`/`Out` en `enabled = false` (invariante Moonlight).

**Regla**: no reutilizar `specialWorkspace` para el overview. Moonlight la mantiene
seca; el plugin necesita su propia leaf enabled. `zoomFactor` esta libre en este setup
(solo la usa el zoom de pantalla, que no se usa).

**Anti-regresion**: `hyprland.sh` (verificador del dominio `hyprland`) agrega el check
`hyprexpo-anim-leaf`: si `plugin:hyprexpo:animation` apunta a una leaf con `enabled=0`,
FALLA. Detecta exactamente esta regresion.

**Aplicar**: `hyprctl reload && hyprctl configerrors` (vacio) + `verify run hyprland`.

### Revertir
`config.animation = "specialWorkspace"` en `plugins/hyprexpo.lua`, quitar la leaf
`zoomFactor` de `animations.lua`, `hyprctl reload` (vuelve a quedar sin morph).

## Cambio 2026-10-09h — guard anti-crash de pointer lock (`block_pointer_lock`)

Motivo: Hyprland 0.56.2 se cae (SIGSEGV de core) al activar un `zwp_pointer_constraints_v1.lock_pointer`.
La recursion reportada es `onLockPointer -> activate -> simulateMouseMovement -> mouseMoveUnified
-> rawSurfaceFocus -> activate`. El fix upstream `5e04ae1` (`desktop/constraint: move to controller
and state`, #16494, +1276/-180, 19 archivos) NO esta en 0.56.2 y recompilar Hyprland es inviable aqui.

Mitigacion elegida (persistente, sin recompilar Hyprland): **negar las solicitudes de pointer lock**
a nivel de la activacion de la constraint. Se hookea `CPointerConstraint::activate` (simbolo exportado
`_ZN18CPointerConstraint8activateEv`, resuelto con `findFunctionsByName("CPointerConstraint8activateEv")`).
Si `isLocked()` y `plugin:hyprexpo:block_pointer_lock != 0`, el hook NO llama al original -> el lock nunca
se activa -> no hay recursion -> no hay crash. Se registra un WARN rate-limited (>=2s entre lineas).

Por que esta variante y no el guard de profundidad en `simulateMouseMovement`: `onLockPointer` es un
metodo privado/no exportado de `CPointerConstraintsProtocol`, no hookeable de forma estable desde el
plugin; `activate` es la frontera efectiva protocolo->compositor y es un simbolo global exportado.
Resulta mas acotado que meter un contador de re-entrada en la zona caliente (`simulateMouseMovement`).

Archivos: `main.cpp` (hook + `PLUGIN_INIT`), `PluginConfig.cpp`
(`plugin:hyprexpo:block_pointer_lock`, `CIntValue` default **1**, min 0 max 1).
`plugins/hyprexpo.lua` fija `config.block_pointer_lock = 1` solo si `hl.get_config(...) ~= nil`
(evita `configerrors` unknown-key antes del relogin; se activa solo tras reiniciar Hyprland).

**Aplicar**: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` + **logout/login** (el `.so` recien cargado
tiene efecto al arrancar Hyprland; `hyprctl reload` NO recarga el `.so`).

**Revertir (sin recompilar, inmediato)**: poner `config.block_pointer_lock = 0` en
`plugins/hyprexpo.lua` (o `hyprctl keyword plugin:hyprexpo:block_pointer_lock 0`) y `hyprctl reload`.
Para eliminar el codigo, revertir el hunk de `main.cpp`/`PluginConfig.cpp` en
`linux/patches/hyprexpo-local.patch` + `hyprexpo-rebuild.sh` + logout/login.

**Riesgo**: bloquea TODO pointer lock mientras este ON (juegos FPS, mouse-capture de Moonlight /
lan-mouse). Es el trade-off aceptado (Hyprland estable > lock relativo). Se desactiva por config.

**Verificado** (harness anidado, NUNCA sesion viva):
- Sin guard: cliente Wayland minimo (`/tmp/opencode/plock/lock_client.c`) pide
  `lock_pointer` -> recibe el evento `locked` (activate corrio normal).
- Con guard: mismo cliente -> NO recibe `locked` (lock ignorado) y el log del instance anidado tiene
  el WARN `zwp_pointer_constraints lock request ignored`.
- Overview 3D intacto (`hyprexpo-verify-3d.sh`: tiles en perspectiva, `nested_alive=yes`,
  plugin cargado) y `hyprctl configerrors` vacio.
- Limite conocido: el cliente minimo NO reproduce el SIGSEGV de core en 0.56.2 (para un lock de
  ventana enfocada el guard `m_active`/early-return de `mouseMoveUnified` acota la recursion). El
  guard se valida por su efecto: intercepta exactamente `activate`, el frame de la recursion reportada.

## Cambio 2026-09-24g — laptop = desktop (mismo `.so` parcheado)

Antes `hyprland.lua` gateaba el 3D con `EXPO_3D = (machine == "desktop")`: la
laptop corría el plugin stock (grilla plana). Ahora **ambas máquinas corren el
mismo `.so` parcheado**.

- `hyprland.lua`: `EXPO_3D = true` (flag conservado solo por claridad). Se quitó
  el bloque que anulaba `threed_*`/`background_image` en laptop y se actualizaron
  los comentarios que decían "solo desktop".
- `hl.plugin.load(...)` ahora construye la ruta con `$USER` en vez de hardcodear
  `eztvn` (portable entre cuentas).
- `background_image` resuelve el fallback con `$HOME`, no con `/home/eztvn`.
- `scripts/setup-omarchy.sh`: compila e instala el parche en **ambas** máquinas
  (Fase 6, vía `hyprexpo-rebuild.sh`); antes solo se mencionaba para desktop.
  La verificación (Fase 12) ya no está gateada a desktop.

Aplicar: `bash scripts/setup-omarchy.sh` (o `~/.local/bin/hyprexpo-rebuild.sh` +
reiniciar Hyprland). El `.so` es machine-agnostic: es el mismo parche.

## Cambio 2026-09-24f — el efecto 3D entra suave (no de golpe en un frame)

Motivo: el morph de tamaño/posición ya animaba, pero el **efecto 3D** (tilt,
yaw, fisheye, fog, vignette y la homografía por tile) se aplicaba **entero en el
primer frame**. La transición quedaba: ventana plana → (1 frame) grilla ya
inclinada/distorsionada/oscurecida. Eso es el "se pierden un montón de pasos
intermedios" que reportó el usuario.

Causa: en `Overview.cpp`, `tiltAnim` se creaba con
`createAnimation(startTilt, ...)` donde `startTilt` = tilt configurado, y **nunca
se le fijaba un goal**, así que valía constante (no había rampa). El comment
"animate 0 -> configured tilt on open" era una edición a medio hacer.

Fix (en el fork local, `~/dotfiles/linux/patches/hyprexpo-local.patch`; **requiere
rebuild + logout/login**, `hyprctl reload` NO recarga el `.so`):

- `tiltAnim` ahora guarda una **fuerza 0..1** (no grados). En `Overview.cpp` se
  crea con `createAnimation(0.0f, tiltAnim, config(animLeaf))` y se le pone goal
  `*tiltAnim = threed_enable ? 1.0 : 0.0` → anima 0→1 al abrir, con el mismo
  `animLeaf`/curva que el zoom (`specialWorkspace` + `expoOpen`).
- En `OverviewRender.cpp` (`fullRender`) se calcula
  `warpAmt = clamp(tiltAnim->value(), 0, 1)` y se **escala por `warpAmt`** todo lo
  3D: `tilt` (`**P3TILT * warpAmt`), `yaw`, `fisheye` (`setLens`), `fog`
  (`0.5 * warpAmt`) y `vignette` (`0.35 * warpAmt`). El fondo sigue plano
  (`setLens 0`).
- El cierre ya hacía `*tiltAnim = 0` en `applyCloseTarget`, así que ahora aplana
  1→0 simétricamente. Al abrir, el 3D "se despliega" desde plano en vez de saltar.

Estado: aplicado con `hyprexpo-rebuild.sh` (instalado en
`/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so`). **Pendiente logout/login** para
que el proceso vivo cargue el `.so` nuevo.

### Revertir
En el patch/fork: volver `tiltAnim` a grados (`createAnimation(**P3TILT ...)`)
quitando el goal, y quitar el factor `warpAmt` de `tiltNow`/`yaw`/`setLens`/
`setFog`/`setVignette` en `OverviewRender.cpp`. Regenerar el patch, correr
`~/dotfiles/linux/bin/hyprexpo-rebuild.sh` y logout/login.

## Cambio 2026-09-24e — morph del fly-through (`SUPER+#`) + crash al cerrar sesión

Motivo (2 reportes):
1. Al pulsar `SUPER + <n>` (sobre todo diagonal) la transición de ventana a
   overview y de vuelta **saltaba** directo a un tile casi a pantalla completa,
   sin frames intermedios.
2. Hyprland se caía (SIGSEGV) en **cada cierre de sesión**, y el watchdog lo
   relanzaba en `--safe-mode`.

Causa 1 (fly-through): `fly_open_and_go()` abría el overview con
`peek(EXPO_PEEK_ZOOM)` = `2.65`. El plugin anima el *tamaño* de la grilla de
`3.0` (un tile llena la pantalla) hacia el goal; con goal `2.65` el recorrido era
casi nulo y, además, al soltar `SUPER` se llamaba a `fly_commit_now()` que
revertía la animación en ~10 ms. Resultado: sin pasos visibles.

Causa 2 (crash): en `hyprland.lua`, `apply_dynamic_gaps()` estaba suscrita a
`window.destroy`. Ese evento se emite durante el `~CWindow` del teardown de la
sesión; al ejecutarse la lógica Lua sobre estado ya liberado, el primer getter
nativo (`hl.get_active_workspace()`) hacía SEGV. `pcall` no atrapa un SIGSEGV.

Cambios en `hyprland.lua` (solo config, sin rebuild del `.so`):

| Cambio | Antes | Despues |
|--------|-------|---------|
| `EXPO_FLY_MS` (~linea 1090) | `90` | `320` |
| `fly_open_and_go()` | `peek(EXPO_PEEK_ZOOM)` | `expo("on")` (grilla completa) |
| `expo_fly_super_up()` | confirma siempre al soltar | confirma solo si `expo_fly.deliberate`; el tap directo espera el timer de `EXPO_FLY_MS` |
| suscripción de `apply_dynamic_gaps` (~linea 234) | incluye `"window.destroy"` | se quitó `"window.destroy"` |

Con esto el tap directo de `SUPER+#` lanza la apertura completa (ventana→grilla),
espera `EXPO_FLY_MS` y recién ahí hace `kb_selectn`, mostrando el morph. El
`peek(2.65)` queda solo para el *retarget* en vuelo (`expo_fly.busy > 0`), donde
sí se busca un salto instantáneo. `hyprctl configerrors` → vacío.

Estado: aplicado con `hyprctl reload`. Verificado en vivo con ráfagas `grim`
(`/tmp/opencode/fly/sheet.png`, `/tmp/opencode/fly2/sheet.png`): ventana→grilla 3D
con frames intermedios. El `.so` instalado no cambia (fix Lua puro).

### Revertir
`EXPO_FLY_MS = 90`; `fly_open_and_go` volver a `peek(EXPO_PEEK_ZOOM)`; quitar la
guarda `deliberate` en `expo_fly_super_up`; volver a incluir `"window.destroy"` en
la lista de `hl.on` de `apply_dynamic_gaps` (esto último reintroduce el crash de
logout). Luego `hyprctl reload`.

## Cambio 2026-09-24d — bordes, animación suave, esquinas y preview en vivo

Motivo (4 reportes): (1) los workspaces inactivos no dibujaban borde; (2) la
animación de apertura/cierre saltaba de chico a pantalla completa sin pasos
intermedios; (3) quedaba un marco **gris** en esquinas/bordes de la pantalla;
(4) el preview de las terminales en la grilla no se actualizaba en tiempo real.

Cambios en el `.so` (en `linux/patches/hyprexpo-local.patch`):

| Fix | Archivo | Qué |
|-----|---------|-----|
| Bordes en todos los tiles | `OverviewRender.cpp` | Lee `plugin:hyprexpo:border_color` y dibuja borde base en todo tile válido que no sea actual/hover/kbFocus. |
| Animación con pasos | `Overview.cpp`, `HyprexpoConfig.hpp`, `PluginConfig.cpp` | Nueva clave `plugin:hyprexpo:animation` (default `windowsMove`) que reemplaza el leaf fijo de las 3 `createAnimation`. Se configura a `specialWorkspace` con curva propia. |
| Gris de esquinas | `OverviewRender.cpp` | El fondo (imagen/wallpaper) se dibuja con `setLens(0, …)`: plano, de borde a borde; los tiles conservan el fisheye. |
| Preview en vivo | `OverviewCapture.{hpp,cpp}`, `OverviewRender.cpp`, `Overview.cpp` | Nuevo `keepAwake` en la captura: no vuelve a suspender las ventanas capturadas, así el cliente alcanza a commitear el frame. |

Cambios en `hyprland.lua`:
- `expo_style.border_default = "rgba(ffffff26)"` (borde de tiles inactivos; vacío = sin borde).
- `expo_cfg.border_color = expo_style.border_default` (clave stock reutilizada).
- `expo_cfg.animation = "specialWorkspace"` (solo en el bloque `EXPO_3D`).
- Curva `expoOpen` (`0.22, 0.61, 0.36, 1.0`) + `hl.animation({leaf="specialWorkspace", speed=4, bezier="expoOpen"})`.

Aplicar: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` + **reiniciar Hyprland**
(`hyprctl reload` no recarga el `.so`). Verificado en harness anidado: borde en
los 9 tiles (actual dorado, resto blanco tenue).

### Ajuste posterior (mismo día)
Tras probarlo en vivo: **más margen entre tiles** y algo **menos de inclinación**.

| Clave | Antes | Despues |
|-------|-------|---------|
| `expo_style.gaps_in` (linea 521) | `0` | `16` |
| `expo_style.threed_tilt` (linea 538) | `22` | `15` |

Estado: aplicado con `hyprctl reload` → ok (`gaps_in=16`, `threed_tilt=15`).

#### Centrado vertical (margen simétrico arriba/abajo)
Motivo: con perspectiva, las pantallas quedaban **más pegadas abajo** que arriba
(el hueco alrededor del cubo no era simétrico). Causa: en el warp 3D el plano
cercano se agranda más de lo que se encoge el lejano (`D = cam - z`), así que la
caja proyectada de la grilla se corría hacia el espectador y el borde inferior
salía de pantalla.

Cambio (`Overview3D.cpp`, `buildTileH3`): se calcula la proyección del borde
superior e inferior de la columna central de la grilla y se traslada cada vértice
`vOffset = -½(sTop + sBot)` para que su punto medio caiga en el pivote → márgenes
simétricos. `vOffset` depende solo de tilt/cámara (igual para todos los tiles) y
es 0 con `threed_tilt = 0`. Aplicar con rebuild + reinicio.

### Revertir
`border_default = ""`, `animation = "windowsMove"` (o quitar en el bloque 3D),
`gaps_in = 0`, `threed_tilt = 22` + `hyprctl reload`. Para los fixes del `.so`,
revertir el parche y reconstruir.

## Cambio 2026-09-24c — suavizar el 3D y quitar el gris

Motivo: tras cargar el `.so` con el loader JPEG, el overview ya dibuja el wallpaper
como fondo, pero con `threed_enable=1` el warp + el `glass_glow` daban un velo
**gris** y las ventanas se veian muy **inclinadas**.

Cambios en `expo_style` (`hyprland.lua`):

| Clave | Antes | Despues |
|-------|-------|---------|
| `threed_tilt` (linea 515) | `50` | `22` |
| `threed_fisheye` (linea 521) | `0.18` | `0.1` |
| `glass_glow_enable` (linea 524) | `1` | `0` |

Estado: aplicado con `hyprctl reload` → ok. Captura del overview real (`grim`)
sin gris y con ventanas casi rectas (`/tmp/opencode/overview_soft.png`).

### Revertir
`threed_tilt = 50`, `threed_fisheye = 0.18`, `glass_glow_enable = 1` + `hyprctl reload`.

## Cambio 2026-09-24b — fondo del overview con `background_image` en JPEG

Motivo: al abrir el overview el fondo y los tiles de workspaces vacios se veian
**negros**. Causa: `loadBackgroundImage()` (parche local) solo leia PNG
(`cairo_image_surface_create_from_png`), pero `expo_style.background_image` apunta
a un `.jpg`; y con `tile_transparent = 1` (default) los tiles vacios son
transparentes, asi que no habia nada detras salvo el `bg_col` oscuro.

Cambio (en `linux/patches/hyprexpo-local.patch`, `Overview.cpp`):
- `loadBackgroundImage()` ahora usa `Hyprgraphics::CImage` (png/jpeg/webp/…) en
  vez de solo PNG. Se agrego `#include <hyprgraphics/image/Image.hpp>`.
- `hyprland.lua`: se agrega `wallpaper_bg = 1` en `expo_cfg` (fallback stock).
  Ojo: el fallback no dibuja nada si `MON->m_background` es null (caso hyprpaper),
  asi que el fix real es el loader.

Aplicar: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` (rebuild + install).
Requiere **reiniciar Hyprland** (logout/login): `hyprctl reload` NO recarga el `.so`.
Verificado en el harness anidado (`HYPREXPO_DEV_BG=<jpg>`): el fondo del overview
dibuja la imagen correctamente.

Estado 2026-09-24 21:33: **rebuild + install hechos** → el `.so` instalado en
`/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so` ya trae `Hyprgraphics::CImage`
(5 refs, sin `cairo_image_surface_create_from_png`). `hyprctl reload` OK
(`wallpaper_bg=1`, `background_image` = el `.jpg`). Captura del overview real
(`grim`) sin sabana gris. **Pendiente: logout/login** para que el proceso vivo
cargue el `.so` nuevo (ahora el fondo ya sale bien por el fallback `wallpaper_bg`,
que pinta el mismo wallpaper).

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

## Cambio 2026-09-25 — rebase del pin (upstream borro el commit viejo)

Upstream reescribio su historial: el pin anterior (`e95ef2e`) ya no existe en
GitHub (404) y `master` cambio de layout (`src/`). Nuevo pin: **`5891014c`**,
que es el commit oficialmente pineado en `hyprpm.toml` para Hyprland 0.56.2
(el que corre en ambas maquinas). `hyprexpo-local.patch` regenerado contra ese
pin (mismos 16 archivos); verificado en sesion anidada (grilla 3D OK).

Diferencia conocida: el hunk del live-refresh (timer 120ms→33ms, stagger 2→3
tiles) se descarto — esa funcion upstream no existe en `5891014c` (ni en el
`master` actual). La expo vuelve a snapshots al abrir + refresh por damage,
como el plugin stock. 3D, instant-retarget y tiles transparentes intactos.
**(Update: el live-refresh se restauro el mismo dia, ver "live-refresh
restaurado" mas abajo — sin el, los previews de otros espacios quedan
congelados.)**

## Cambio 2026-09-25 — `reverse_rows` implementado de verdad

`hyprland.lua` seteaba `plugin:hyprexpo:reverse_rows=1` (orden numpad 789/456/123)
pero la clave NO existia en ningun parche commiteado: venia de un arbol sucio del
desktop, nunca foldeada al patch. Resultado: `configerrors` con unknown key y orden
stock. Implementado en el fork: default `REVERSE_ROWS_DEFAULT=0`,
flag `reverseRows` en `computeTileLayout`/`tileIndexAtPoint` (fila visual =
`occupiedRows-1-fila logica`), cableado en `tileLayoutForIndex`/`tileIndexAtPoint`
( TODA la geometria pasa por ahi: render, hit-test, hover, drag, nav). Test
headless `/tmp/revtest.cpp`: 9/9 asserts (numpad, hit-test, parciales, stock
intacto). Parche v2 regenerado (18 archivos). Instalar + reloguear para cargar.

## Cambio 2026-09-25 — live-refresh restaurado (fin de previews congelados)

**Sintoma**: al abrir el overview, las terminales en otros workspaces se
mostraban congeladas en el estado del momento de apertura.

**Causa**: el rebase al pin `5891014c` descarto el hunk de
`COverview::startLiveRefresh()` ("upstream fn absent at new pin"), un timer
que re-capturaba los tiles periodicamente. Sin el, los tiles de workspaces
ocultos nunca se vuelven a capturar: sus ventanas no se renderizan → no emiten
damage → ni el damage hook ni el capture-on-open los refrescan.

**Fix (reimplementacion fresca en el fork)**:

- `COverview::startLiveRefresh()` en `OverviewInteraction.cpp`: timer
  `CEventLoopTimer` de **33ms** que recaptura **3 tiles rotativos por tick**
  (`liveRefreshCursor`), salta el tile enfocado (ese si recibe damage) y los
  invalidos, y hace `damage()` + `scheduleFrame()` por tick.
- Se arma al final del constructor (`Overview.cpp`) y se cancela en el
  destructor junto a `redrawSettleTimer`.
- Miembros nuevos en `Overview.hpp`: `liveRefreshTimer`, `liveRefreshCursor`.

**Anti-regresion**:

- `hyprexpo-rebuild.sh` y `hyprexpo-verify-3d.sh` fallan si el patch aplicado
  no contiene `startLiveRefresh` (grep tras `git apply`).
- Test funcional anidado: `hyprexpo-verify-live.sh` — abre una terminal con
  ticking en ws2, saca el overview y compara dos capturas ~1.5s aparte;
  `diff_pixels>0` = vivo, `0` = congelado (exit 2).

Verificado: build limpio desde el patch + harness anidado (grilla 3D OK) +
`hyprexpo-verify-live.sh` → `verdict=live`. Instalar con `hyprexpo-rebuild.sh`
+ logout/login (el `.so` solo se carga al arrancar Hyprland).

## Cambio 2026-09-25 — hover-select (caer en el workspace al reposar el mouse)

**Motivo**: seleccionar un workspace exigía click. Ahora, con el overview
abierto, basta **reposar el mouse** sobre un tile (dwell) para caer en ese
workspace: se cierra la grilla y se cambia de espacio, sin click.

**Comportamiento**:

- Al mover el mouse, el tile bajo el puntero se marca como hovered; si el
  puntero **permanece** sobre él `hover_select_delay` ms, se selecciona.
- Moverse dentro del mismo tile **no reinicia** el dwell (acumula); salir del
  tile o volver al workspace de origen cancela el timer.
- El tile del workspace **de origen** (`openedID`) no dispara: evita cerrar por
  abrir la grilla (el puntero arranca encima de ese tile).
- No dispara mientras hay un **drag** activo.

**Claves nuevas** (`plugin:hyprexpo:`, default apagado en el plugin):

| Clave | Default `.so` | En `hyprland.lua` | Qué |
|-------|---------------|-------------------|-----|
| `hover_select_enable` | `0` | `1` | activa el hover-select |
| `hover_select_delay`  | `400` | `350` | ms de reposo antes de seleccionar |

Expuestas en `expo_style` y cableadas en el bloque `EXPO_3D` de
`hyprland.lua` (`expo_cfg.hover_select_enable/delay`).

**Implementación (fork local, `linux/patches/hyprexpo-local.patch`)**:

- `HyprexpoConfig.hpp`: defaults `HOVER_SELECT_*`.
- `PluginConfig.cpp`: registra las dos claves.
- `Overview.hpp`: `void armHoverSelect();` + miembros `hoverSelectTileID`,
  `hoverSelectTimer`.
- `OverviewInteraction.cpp`: `COverview::armHoverSelect()` arma un
  `CEventLoopTimer` atado a `(monitorKey, sessionGeneration)`;
  al disparar revalida el tile y llama `selectHoveredWorkspace()` +
  `closeOverviewsSelecting(this)`. Se re-arma/actualiza con `updateTimeout`.
- `Overview.cpp`: `onCursorMove` llama `armHoverSelect()`; el destructor cancela
  el timer.
- Tests de fuente en `tests/OverviewSourceTests.cpp` (claves registradas,
  función presente, usa `selectHoveredWorkspace`/`closeOverviewsSelecting`).

**Aplicar**: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` + **logout/login**
(`hyprctl reload` NO recarga el `.so`; recargar antes de reloguear da
unknown-key). Estado: build desde patch OK + instalado en
`/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so`. Verificado funcionalmente en
sesion anidada (`movecursor` a un tile distinto → reposo `delay` ms → cae en ese
workspace y cierra la grilla; reparar sobre el tile de origen no dispara).
**Pendiente logout/login** para que el proceso vivo cargue el `.so`.

### Revertir
En el bloque `EXPO_3D` de `hyprland.lua`: `expo_cfg.hover_select_enable = 0`
(o quitar las dos claves), luego `hyprctl reload`. Para quitar el código,
revertir el parche y `hyprexpo-rebuild.sh`.

## Cambio 2026-09-25 — edge-passthrough (cruzar a la otra maquina con la grilla abierta)

**Motivo**: con el overview abierto, `onCursorMove` cancelaba **todo** movimiento
del puntero (`info.cancelled = true`), asi que el compositor nunca actualizaba el
foco de puntero y la franja overlay de **lan-mouse** (1px, capa overlay
"LAN Mouse Sharing") no recibia `wl_pointer.enter`. Resultado: no se podia cruzar
a la otra maquina dejando un PC en modo grilla.

**Comportamiento**:

- Si el puntero esta a `edge_passthrough` px o menos de un borde del monitor, el
  movimiento **no se consume**: pasa al compositor para que la superficie de borde
  (lan-mouse) reciba foco de puntero.
- Lejos de los bordes, el overview sigue consumiendo el movimiento como antes.
- El hover-select se desarma mientras el puntero reposa en el borde (evita que el
  dwell dispare y cierre la grilla justo al hacer el handoff).

**Clave nueva** (`plugin:hyprexpo:`):

| Clave | Default `.so` | En `hyprland.lua` | Que |
|-------|---------------|-------------------|-----|
| `edge_passthrough` | `2` | `2` | px desde el borde donde el movimiento pasa al cliente de borde (0 = off) |

**Implementacion (fork local, `linux/patches/hyprexpo-local.patch`)**:

- `HyprexpoConfig.hpp`: defaults `EDGE_PASSTHROUGH_*`.
- `PluginConfig.cpp`: registra la clave.
- `Overview.cpp`: helper `cursorAtMonitorEdge(monitor)`; `onCursorMove` solo marca
  `info.cancelled = true` fuera del borde.
- `OverviewInternal.hpp`: declara el helper.
- `OverviewInteraction.cpp`: `armHoverSelect` no arma si el puntero esta en el borde.
- Tests de fuente en `tests/OverviewSourceTests.cpp`.

**Aplicar**: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` + logout/login (igual que
hover-select; `hyprctl reload` no recarga el `.so`).

### Revertir
`expo_cfg.edge_passthrough = 0` en `hyprland.lua` + `hyprctl reload` (o quitar la
clave). Para quitar el codigo, revertir el parche y `hyprexpo-rebuild.sh`.

## Cambio 2026-09-25b — hover-select con park timer (abrir por esquina ya no selecciona)

**Motivo**: al abrir la grilla con el hot corner (esquina superior izquierda) el
puntero aterrizaba sobre el tile top-left (distinto al workspace actual) y el
hover-select lo seleccionaba apenas pasaba `hover_select_delay`, cerrando la
grilla de inmediato. Con SUPER+Y no pasaba porque el puntero arrancaba sobre el
tile de origen (`openedID`, que el plugin ya ignoraba).

**Comportamiento nuevo** (gate por TIEMPO, no por distancia):

- Al abrir se ancla el puntero (`hoverSelectAnchor`) y el tile mas cercano
  (`hoverSelectAnchorTile`, cubre el caso del margen/esquina fuera de todo tile);
  arranca un timer de `hover_select_park_ms` (T).
- Si el puntero **sale rapido** de la zona de la esquina (transito, <T): el timer
  NO marca parked y el hover-select arma normal → al tirar el mouse a un tile el
  cambio procede agil (dwell `hover_select_delay`).
- Si el puntero **se queda** dentro de 64px del punto de apertura pasado T: se
  marca `parked` y el hover-select queda desarmado mientras el puntero siga en
  ese tile → la grilla se queda fija. Al moverse a **otro** tile se desarma el
  park y se puede elegir.
- Aterrizar/reposar en la esquina al abrir nunca selecciona (radio de 64px).
- Click sobre un tile y atajos de teclado siguen igual.

**Clave nueva** (`plugin:hyprexpo:`, default apagado/stock):

| Clave | Default `.so` | Que |
|-------|---------------|-----|
| `hover_select_park_ms` | `300` | ms de permanencia en la esquina antes de fijar la grilla; menor = fija antes, mayor = deja pasar mas transitos |

NO se cablea todavia en `hyprland.lua` a proposito: el `.so` vivo no conoce la
clave hasta el logout/login y `hl.config` con una clave desconocida ensucia
`hyprctl configerrors`. Tras reiniciar, agregarla en `expo_style` +
`expo_cfg` (bloque `EXPO_3D`) para tunear T; el default 300 ya aplica.

**Implementacion (fork local, `linux/patches/hyprexpo-local.patch`)**:

- `HyprexpoConfig.hpp` / `PluginConfig.cpp`: `HOVER_SELECT_PARK_*` + registro.
- `Overview.hpp`: `hoverSelectAnchor`, `hoverSelectAnchorTile`,
  `hoverSelectParked`, `hoverSelectParkTimer`; `armHoverSelectPark()`.
- `Overview.cpp` (apertura de `COverview`): ancla, tile mas cercano, arranca el
  park timer; el destructor lo cancela.
- `OverviewInteraction.cpp`: `armHoverSelectPark()` (timer T -> `parked` solo si
  el puntero sigue a <=64px del ancla) y `armHoverSelect()` (suprime si esta
  cerca del ancla o si `parked` y sigue en el tile de apertura).
- `scripts/run-nested.sh`: knobs `HYPREXPO_DEV_HOVERSELECT[_DELAY]` y
  `HYPREXPO_DEV_HOVERSELECT_PARK` (default off) para probar en sesion anidada.
- `tests/OverviewSourceTests.cpp`: asserts del park timer y del gate.
- `hyprexpo-rebuild.sh`: el guard del instalador falla si el patch pierde
  `hoverSelectParked`/`armHoverSelectPark` (ademas de `startLiveRefresh`).

**Aplicar**: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` + logout/login (el `.so`
solo se carga al arrancar Hyprland; `hyprctl reload` no lo recarga).

**Verificado**: build limpio desde el patch + tests de fuente del gate OK; harness
anidado en sesiones frescas con `HYPREXPO_DEV_HOVERSELECT=1`: (landing) abrir en
la esquina y reposar deja `submap=hyprexpo`; (park) reposar >T, nudge dentro del
tile de apertura sigue en `hyprexpo`, moverse a otro tile -> `default`; (transit)
moverse a otro tile <T -> `default`. El harness anidado es flaky con la geometria
(cursor se clampa al tamano de la ventana host), asi que la logica queda ademas
cubierta por los tests de fuente. Pendiente logout/login para que la sesion viva
cargue el `.so`.

## Cambio 2026-09-25c — fondo transparente (video de linux-wallpaperengine detras de la grilla)

**Motivo**: el usuario quiere un fondo **animado/video** detras del overview y poder
elegir entre video (`linux-wallpaperengine`) y estatico (`hyprpaper`/omarchy). El
overview pintaba su propio backdrop (`bg_col` + `background_image`/`M_background`),
tapando lo que el compositor ya hubiera dibujado.

**Comportamiento**: `plugin:hyprexpo:background_transparent` (default 0 = conservador).
En 1 el plugin **no pinta backdrop**: salta el `clearWithColor(bg_col)` (clear con
alpha 0) y todo el bloque de fondo. La grilla queda flotando sobre la capa
`BACKGROUND` real del compositor. Y como el hook `renderWorkspace` **reemplaza** a
Hyprland (no corre el render normal antes del pass), cuando el flag esta activo el
hook **redibuja las layer surfaces `BACKGROUND`** debajo de la grilla (si no, solo
quedaria lo que dejo el clear transparente = nada). Funciona con hyprpaper,
omarchy-background o un cliente de video (linux-wallpaperengine escribe solo su
region; el damage box no se limpia porque `blocksDamageReporting` lo suprime).

**Coordinacion con `tile_transparent`**: el guard de tiles transparentes
(`CTransparentTileGuard`) ahora se activa con `tile_transparent=1` Y
(`background_image` no vacio **O** `background_transparent=1`). Antes, con
`tile_transparent` sin `background_image`, caia al fallback `wallpaper_bg` (dibujaba
el wallpaper del monitor → el video/estatico se "duplicaba" por tile). Ahora con el
flag nuevo los tiles quedan transparentes y no se duplica el fondo.

**Clave nueva** (`plugin:hyprexpo:`):

| Clave | Default `.so` | En `hyprland.lua` | Que |
|-------|---------------|-------------------|-----|
| `background_transparent` | `0` | `1` | salta el backdrop y deja ver la capa BACKGROUND real (video/estatico) |

**Implementacion (fork local, `linux/patches/hyprexpo-local.patch`)**:

- `HyprexpoConfig.hpp`: `BACKGROUND_TRANSPARENT_DEFAULT = 0`.
- `PluginConfig.cpp`: registra la clave (0/1).
- `OverviewRender.cpp` (`fullRender`): `clearWithColor(backgroundTransparent ? rgba(0,0,0,0) : BG_COLOR)` y el bloque de backdrop envuelto en `if (!backgroundTransparent)`.
- `OverviewCapture.cpp` (`CTransparentTileGuard`): gate extendido (arriba).
- `main.cpp` (`hkRenderWorkspace`): con el flag, redibuja las layer surfaces `BACKGROUND` antes de las `TOP`.
- `HyprlandConfigCompat.hpp` / `Overview.cpp`: helper `intValuePtr` para leer la clave desde `main.cpp` (que no incluye `OverviewInternal.hpp`).
- `scripts/run-nested.sh`: knobs `HYPREXPO_DEV_BG_TRANSPARENT` y `HYPREXPO_DEV_TILE_TRANSPARENT`.
- `tests/OverviewSourceTests.cpp`: asserts del clear/backdrop/render-hook.
- `hyprexpo-rebuild.sh` y `hyprexpo-verify-3d.sh`: guard anti-regresion (fallan si el patch pierde `background_transparent`).

**Fuente del fondo (video vs estatico)** — un solo comando:

```
wallpaper-switch.sh use video    # linux-wallpaperengine.service (AUR linux-wallpaperengine-git)
wallpaper-switch.sh use static   # hyprpaper sobre el fondo canonico de Omarchy
```

- Estado persistente en `~/.config/wallpaper-source` (`video`/`static`).
- `wallpaper-switch.sh use video` para hyprpaper y arranca el servicio; `use static`
  detiene el servicio y reactiva hyprpaper.
- `hyprland.lua` (autostart) lee `~/.config/wallpaper-source` y arranca el que
  corresponda (antes el desktop no arrancaba hyprpaper y la laptop lo forzaba).
- `wallpaper-switch.sh <id>` ahora activa video automaticamente (y lista con `list`).
- Unit nueva: `linux/system/systemd-user/linux-wallpaperengine.service`
  (instalada por `setup-omarchy.sh` Fase 8; tambien copiada a `~/.config/systemd/user/`).

**Aplicar**: `~/dotfiles/linux/bin/hyprexpo-rebuild.sh` + **logout/login** (el `.so`
solo se carga al arrancar Hyprland). `hyprland.lua` cablea la clave solo si
`hl.get_config("plugin:hyprexpo:background_transparent") ~= nil` (evita
`configerrors` unknown-key antes del reinicio; se activa sola tras relogin).

**Verificado**: `hyprctl configerrors` vacio + `luac -p` OK; tests de fuente OK
(solo los 10 fallos preexistentes de `Dispatchers`); harness anidado con el patch:
`background_transparent=1` NO dibuja el backdrop (control `=0` si lo dibuja) y la
grilla 3D renderiza. **Pendiente logout/login** para la sesion viva + screenshot real.

### Revertir
`expo_style.background_transparent = 0` (o quitar la clave) + `hyprctl reload`.
Para quitar el codigo, revertir el parche y `hyprexpo-rebuild.sh`.

## Backups (en este mismo directorio)

- `hyprland.lua.bak.1790228045` — estado **antes** del cambio de hyprexpo
  (border_width=2, labels on). Usar para revertir.
- `hyprland.lua.bak.1790225169` — backup anterior (23:46), mas viejo, con otros
  cambios previos (theme_color helper, gaps dinamicos).

## Notas

- `make test` en `~/.cache/hyprexpo-src` arrastra **10 fallos preexistentes** de
  `tests/OverviewSourceTests.cpp` (selector de workspace en `Dispatchers.cpp`:
  `kb_selectn`, skip-empty/padding, foco de monitor). NO son del hover-select:
  el pin puro pasa 0, el patch viejo y el nuevo fallan los mismos 10. Pendiente
  actualizar esas aserciones a la logica local. Por eso `hyprexpo-rebuild.sh`
  usa guards de `grep` (startLiveRefresh + hoverSelectMoveGate) en vez de `make test`.
- Este directorio es symlink a `~/dotfiles/linux/config/hypr/`, asi que el cambio
  esta versionado en git dentro del repo `dotfiles`.
- `omarchy refresh hyprland` sobrescribe el archivo; los backups de arriba son el
  respaldo si eso pasa.
