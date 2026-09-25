---
name: hyprland-plugin-safety
description: >
  Trabajar de forma segura con hyprland.lua y los plugins de Hyprland (hyprpm).
  Evita tumbar el compositor a safe-mode al compilar/instalar el .so de un plugin
  o al editar su config Lua. Trigger: hyprland.lua, hyprpm, plugin de Hyprland,
  hyprexpo, hyprbars, safe-mode, SIGILL, "Hyprland crasheó", "plugin crash",
  configerrors, "Couldn't connect to .socket.sock", fly-through entre
  workspaces, transicion desktop→grilla→desktop, keybind SUPER+numero.
---

# Hyprland: config Lua + plugins sin romper la sesión

## Regla de oro (el error que causó el crash)

**NUNCA** compilar ni reemplazar a mano el `.so` de un plugin gestionado por
hyprpm usando un commit distinto al que hyprpm tiene **pinneado** para la versión
de Hyprland que está corriendo.

Aunque compile bien y el hash de API coincida, una revisión distinta del plugin
puede ser ABI-incompatible → el plugin ejecuta código mal → **SIGILL** al usarlo →
Hyprland crashea → el watchdog lo relanza en `--safe-mode` (sin tu config ni
plugins), y `hyprctl` deja de conectar.

Caso real: se construyó `hyprexpo.so` desde `HEAD` (main) en vez del commit
pinneado para Hyprland 0.56.2. El `.so` cargó, pero crasheó al commitear una
ventana. La solución fue reconstruir desde el commit del pin.

## Procedimiento seguro para modificar un plugin hyprpm

1. **Detectar la versión/commit de Hyprland en ejecución:**
   ```sh
   hyprctl version        # anota el "commit" (40 hex)
   ```
2. **Leer el pin del plugin:** en el repo del plugin, `hyprpm.toml` →
   tabla `commit_pins` (mapea commit de Hyprland → commit del plugin).
   ```sh
   grep -n -A40 'commit_pins' /ruta/al/plugin/hyprpm.toml
   ```
3. **Trabajar SIEMPRE en ese commit pinneado** (no en `HEAD`/`main`):
   ```sh
   git checkout <commit-del-pin>
   ```
4. **Compilar con el Makefile del repo** (usa los headers de hyprpm):
   ```sh
   cd /ruta/al/plugin && make -j"$(nproc)"
   ```
   Los headers viven en `/var/cache/hyprpm/<usuario>/headersRoot`.
5. **Verificar la versión embebida** del `.so`:
   ```sh
   strings hyprexpo.so | grep -m1 'v0\.'
   ```
6. **PROBAR en una sesión anidada antes de tocar la real** (si el repo lo trae):
   ```sh
   scripts/run-nested.sh      # HYPREXPO_DEV_SO=... HYPREXPO_DEV_LAYOUT=grid|scrolling
   ```
7. **Instalar** (ruta del cache de hyprpm, root):
   ```sh
   sudo cp hyprexpo.so /var/cache/hyprpm/<usuario>/<plugin>/hyprexpo.so
   ```
8. **Recargar**:
   ```sh
   hyprpm reload      # o: hyprctl plugin unload <path> && hyprctl plugin load <path>
   ```

Prueba rápida de que carga sin crashear (instancia viva):
```sh
hyprctl plugin load /ruta/hyprexpo.so   # -> ok, Hyprland sigue vivo
hyprctl plugin list
hyprctl plugin unload /ruta/hyprexpo.so
```

## Editar la config de plugins en hyprland.lua

- Se configura con `hl.config({ plugin = { <plugin> = { ... } } })`.
- Las claves de plugin **solo son válidas si el plugin está cargado**; si no,
  `hyprctl configerrors` reporta `unknown config key 'plugin.<x>.<y>'`.
- En modo Lua los dispatchers de plugin se llaman con `hl.plugin.<plugin>.<fn>(...)`,
  **no** con `hyprctl dispatch plugin:<...>`:
  ```lua
  hl.bind(mainMod .. " + Y", function()
      hl.plugin.hyprexpo.expo("toggle")
  end)
  ```
- Tras cada edición:
  ```sh
  hyprctl reload && hyprctl configerrors
  ```

## Si Hyprland crashea o entra en safe-mode

- `hyprctl` falla con `Couldn't connect to /run/user/1000/hypr/<sig>/.socket.sock`:
  la variable `HYPRLAND_INSTANCE_SIGNATURE` apunta a la instancia muerta. Busca la
  viva y úsala:
  ```sh
  ls -t /run/user/1000/hypr/ | head -1
  HYPRLAND_INSTANCE_SIGNATURE=<sig-viva> hyprctl version
  ```
- Log de la instancia: `/run/user/1000/hypr/<sig>/hyprland.log`.
- Backtrace del crash: `coredumpctl list` → `coredumpctl info <pid>`.
  `Signal 4 (ILL) ILL_ILLOPN` con un frame en el `.so` del plugin = build
  incompatible.
- Salir de safe-mode = reiniciar Hyprland (operación **disruptiva**: cierra apps).
- Causa más común de safe-mode tras tocar plugins: `.so` de revisión equivocada.

## Verificación rápida

```sh
hyprctl version | grep -i commit
grep -n -A40 'commit_pins' <repo>/hyprpm.toml
hyprctl plugin list
hyprctl configerrors
```

## Caso local: hyprexpo (patch `reverse_rows`)

- Plugin: fork `sandwichfarm/hyprexpo`, gestionado por hyprpm.
- Patch local (no upstream): opción `plugin:hyprexpo:reverse_rows` que invierte
  las filas de la grilla → orden numpad `789 / 456 / 123`.
- Archivos del patch: `HyprexpoConfig.hpp` (+1), `PluginConfig.cpp` (+1),
  `Overview.cpp` (+16, swap de filas tras el cap de `max_workspace`, antes de
  `if (dynamicGrid)`).
- Segundo patch local (fix de animacion, `OverviewRender.cpp`, +19/-1), dos partes:
  1. `close()` hacia OTRO desktop (via dispatcher del plugin): asignar
     `startedOn = NEWIDWS` ANTES de `Config::Actions::changeWorkspace(NEWIDWS)`
     (revertir a `OLDWS` si falla), para que `shouldRenderOverviewForMonitor()`
     no descarte el overview durante los eventos sincronicos de `changeWorkspace`.
  2. `onWorkspaceChange()` (path REAL del usuario: estando en el expo apretar el
     keybind normal `SUPER+N`, no el dispatcher del plugin): asignar
     `startedOn = MON->m_activeWorkspace` antes de `close()`. Sin esto el guard
     `MON->m_activeWorkspace != startedOn` tiraba el overview y se veia el cambio
     de desktop pelado, sin morph.
- Tercer patch local (LIVE PREVIEW, tiles en tiempo real): `Overview.cpp` (+24),
  `Overview.hpp` (+7), `OverviewRender.cpp` (+63). Nuevo `COverview::startLiveRefresh()`
  (llamado al final del constructor, cancelado en el destructor) con un
  `CEventLoopTimer` de 120ms: cada tick re-captura todos los tiles MENOS el
  `openedID` (evita parpadeo del tile enfocado) via `redrawID(i)`, luego
  `damage()` + `MON->scheduleFrame()`. El timer se auto-cancela si `closing` o si
  el overview cambio de generacion. Por que funciona:
  - `hkAddDamageA/B` solo re-capturan el tile del monitor donde hubo dano
    (`OV->onDamageReported()` → `redrawID(openedID)`), o sea el desktop ACTUAL;
    por eso los demas tiles quedaban congelados hasta un re-render completo.
  - `activateWorkspaceForPreview()` reasigna `m_activeWorkspace` temporalmente
    para renderizar un workspace no-activo, y lo restaura (via CScopeGuard), por
    eso se puede capturar tiles de otros desktops sin romper la sesion.
  - Las capturas deben ocurrir en el hilo del event loop (aqui, dentro del timer),
    NO dentro del hook de dano (durante render) — ahi crashea.
  - Costo: re-render N tiles cada 120ms con la grilla abierta. Ajustable el
    intervalo en `startLiveRefresh()` (120ms).
- Debe reconstruirse SIEMPRE sobre el commit del pin (ver `hyprpm.toml`), nunca
  sobre `HEAD`, o Hyprland crashea a safe-mode.
- **Estabilidad observada (Hyprland 0.56.2 + pin 5891014):** abrir/cerrar la
  grilla y cambiar de desktop (keybind normal `SUPER+N`) es estable (probado 8
  ciclos). PERO sacar un screenshot (`grim`, tecla ImprPant de omarchy) justo
  durante la transición de cierre puede tirar `SIGSEGV` en
  `Render::IHyprRenderer::damageSurface` (use-after-free del pass element del
  overview) → watchdog → `--safe-mode`. Evitar capturas en plena animación; si
  se necesita, subir temporalmente `windowsMove.speed`.
- **Salir de safe-mode:** `hyprctl eval 'hl.dispatch(hl.dsp.exit())'` contra el SIG
  vivo (`ls -t /run/user/1000/hypr/ | head -1`). Ojo: con el plugin cargado la
  salida tira `SIGSEGV` en el `PLUGIN_EXIT` (destrucción de overviews), pero el
  exit se completa igual y SDDM reingresa a la sesión normal.
- Nota: en este build `--safe-mode` NO deshabilita plugins (`hyprctl plugin list`
  aún los muestra); igual crashea el plugin si el .so es incompatible.
- Config en `hyprland.lua`:
  ```lua
  hl.config({ plugin = { hyprexpo = {
      columns = 3, rows = 3, dynamic_grid = 0, skip_empty = 0,
      max_workspace = 9, reverse_rows = 1,
      workspace_method = "first 1",
  } } })
  hl.bind(mainMod .. " + Y", function() hl.plugin.hyprexpo.expo("toggle") end)
  ```

## Archivos del patch (resumen)

Build sobre el pin: `cd <repo> && export PKG_CONFIG_PATH="/var/cache/hyprpm/eztvn/headersRoot/share/pkgconfig:$PKG_CONFIG_PATH" && make -j$(nproc)`.
Diff total vs pin = `HyprexpoConfig.hpp +1`, `Overview.cpp +24`, `Overview.hpp +7`,
`OverviewRender.cpp +63/-1`, `PluginConfig.cpp +1`. Un solo `g++` invocation (Makefile
del pin) → `hyprexpo.so`. Instalar con `sudo -n cp` al cache de hyprpm y
`hyprctl plugin unload/load`.

## Fly-through entre workspaces (SUPER+#) en `hyprland.lua`

Objetivo: que cambiar de desktop con `SUPER+#` se sienta tridimensional, pasando
por la grilla. En el bloque de WORKSPACES (`ws_keys`):

- `SUPER+#` llama a `expo_focus(i)`, que abre la grilla (`expo("on")` = morph
  desktop→grilla) y tras `EXPO_FLY_MS` entra al tile (`kb_selectn(i)` = morph
  grilla→desktop). `EXPO_FLY_MS` (arriba del bloque, hoy 200) es el respiro de la
  grilla: mas alto = mas pausado/comodo.
- El morph en si usa la curva `windowsMove` de la config de animations.
- Solo hay tiles para 1..9 (grilla 3x3); `#`=10, o sin plugin, cae a focus normal.
- Repetir la tecla del desktop actual va a `"previous"`.

Hechos de la API (por que la implementacion es como es):

- `expo("on")` es **idempotente** mientras exista algun overview (aunque este
  cerrándose): `onExpoDispatcher` hace `if (overviewOpen()) return {};`. Solo
  reabre cuando `g_overviews` esta vacio (tras `removeOverview`).
- `COverview::selectWorkspaceByID()` **devuelve `false` si `closing == true`**
  (`OverviewInteraction.cpp`), y `onKbSelectNumberDispatcher` no-op si
  `activeOverview()` es null. ⇒ **no se puede re-dirigir un select a mitad del
  cierre**; hay que esperar a que la grilla cierre (g_overviews vacio) y reabrir.
- No existe getter de "overview abierto" en Lua; los dispatchers Lua registrados
  son `expo`, `kb_focus`, `kb_confirm`, `kb_selectn`, `kb_select`, `kb_selecti`,
  `gesture` (`Dispatchers.cpp`).
- `hl.timer(cb, { timeout = ms, type = "repeat"|"oneshot" })` devuelve un timer con
  `set_enabled`/`is_enabled`/`set_timeout` (stub `/usr/share/hypr/stubs/hl.meta.lua`).

Patron robusto: **un solo timer `repeat`** con estado `{want, opened, ticks, age}`
que reintenta `expo("on") + kb_selectn(want)` cada `EXPO_POLL_MS` hasta que
`hl.get_active_workspace().id == want`. Asi el **ultimo** `SUPER+#` siempre gana y
nunca queda pegado en el desktop inicial. Cap de seguridad `EXPO_FLY_MAX` (~4s) →
`expo("cancel")` + focus plano. Bug clasico del enfoque ingenuo (timer oneshot por
pulsacion): `changeWorkspace()` fija `m_activeWorkspace` **sincronicamente** al
empezar el cierre, asi que un segundo press de la misma tecla ve `cur.id == i` y
dispara la rama `"previous"` → salta al workspace de origen.

Interrupcion nativa real (re-dirigir DURANTE el cierre, sin reabrir) requiere
parchear el plugin (permitir `selectWorkspaceByID` con `closing` y re-fijar los
goals de size/pos del close). La solucion actual reabre tras el cierre: ~150-200ms
extra si cambias a mitad.

### Probarlo sin teclado fisico

`wtype` **no** dispara binds del compositor. Exporta temporalmente la funcion y
llamala por eval:

```sh
hyprctl reload                      # tras editar hyprland.lua
hyprctl configerrors                # debe quedar vacio
# (temporal) en hyprland.lua: _G.__hx_focus = expo_focus
hyprctl eval '_G.__hx_focus(5)'
hyprctl eval 'hl.animation({ leaf = "windowsMove", enabled = true, speed = 25, bezier = "default" })'  # ralizar para ver el morph
hyprctl eval 'hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "default" })'   # restaurar
```

Sacar el export temporal despues (no dejar debug en la config).

### Volver al desktop anterior (doble tap) tambien con morph

`expo_fly_back()` da animacion al atajo "apretar la tecla del desktop actual y
volver al anterior": lee el ws actual como destino, abre la grilla (`expo("on")` =
morph desktop→grilla) y en un oneshot tras `EXPO_FLY_MS` hace `kb_selectn(current)`
(grilla→desktop). Alternativa sin grilla: `focus({ workspace = "previous" })` de
Hyprland (animacion slide generica, menos "3D").

**Cuidado con la verificacion:** `hyprctl eval` puede dar `ok` sin ejecutar la
funcion (p.ej. por scoping de la funcion local en el reload). Confirma el efecto
real leyendo el estado (`hyprctl activeworkspace`), no el `ok`. Si un export
temporal `_G.__f = expo_focus` + `hyprctl eval '_G.__f(5)'` no cambia de workspace,
la prueba fue inconclusa (no es que la logica este mal).
