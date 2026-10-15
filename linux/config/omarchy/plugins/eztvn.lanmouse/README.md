# LAN Mouse

Bar widget para [lan-mouse](https://github.com/feschber/lan-mouse): la posición
relativa del otro equipo se elige **arrastrando su pantalla** en un lienzo de
disposición, y se aplica al soltar. También alterna la activación del cliente
y sincroniza la disposición local con Better Displays Pro.

No reinicia el daemon ni toca `config.toml` a mano: todo pasa por el IPC de
lan-mouse (`lan-mouse cli`).

## UI

**Chip en la barra** (sección `right` por defecto)

- Glyph = posición actual del primer cliente (`←` `→` `↑` `↓`).
- Color: `Color.accent` cliente activo, `Color.muted` inactivo,
  `Color.urgent` daemon caído.
- Click izquierdo → abre/cierra el panel. Click derecho → refresca estado.
- Tooltip con host, posición y estado.

**Panel**

| Zona | Qué hace |
|------|----------|
| Hero `lan-mouse` | IP local + host, o el error del daemon; punto de estado |
| `DISPOSICIÓN` | lienzo: pantalla local + tile del peer a escala |
| arrastrar el tile | soltar sobre un borde (izq/der/arriba/abajo) → `lan-mouse cli set-position` + `save-config` |
| status | feedback de la última acción o del daemon |
| `Cliente activo` | `lan-mouse cli activate|deactivate <ID>` |
| `Pantallas` | alinea los monitores locales en una fila horizontal (pipeline de Better Displays Pro) |

Las acciones se encolan: si una corre, la siguiente espera a que termine.

### Lienzo de disposición

- `Model.fitLayout()` coloca local y peer con proporciones lógicas reales y los
  escala a un lienzo de ~210 px con padding `Style.space(14)` y `utilization`
  0.92.
- El peer se dibuja en su posición actual (`lan-mouse cli list`). Al arrastrar,
  `Model.zoneForPoint()` decide el borde destino a partir del centro del tile y
  resalta el hueco con `Model.peerCandidateRect()` antes de soltar.
- `dropRequested(zona)` → `set-position` → `save-config`. La posición se
  previsualiza en el panel y se confirma con el siguiente `cli list`.

### Sincronizar pantallas

`SyncScreensRow.qml` ejecuta el **mismo pipeline que Better Displays Pro** sin
duplicarlo: importa `TopologyModel.js` del plugin vecino, construye la propuesta
con `arrangeEnabledHorizontally` (preserva modo/refresco de cada monitor) y la
aplica con `apply-layout.sh preview` + `keep` (o `revert` si `keep` falla).

- Orden espacial actual → fila horizontal, sin voltear monitores.
- Un solo monitor → no-op («ya está alineada»), sin spawnear procesos.
- `proposed === previous` → no-op inmediato.
- Si `Better Displays Pro` no está instalado, la sección se degrada a un aviso
  (`Loader` + `Loader.Error`).

## Estado: de dónde sale

`lan-mouse cli list` (IPC unix, ~28 ms):

```
id 0: 192.168.1.240:4242 (left) active: true, ips: {192.168.1.240}
```

`Model.js` lo parsea con una regex y devuelve `{id, host, port, position,
active, ips}` por cada línea. Fallback: si el daemon no responde, se parsea
`~/.config/lan-mouse/config.toml` (el chip queda `Color.urgent` y el toggle se
deshabilita). Polling:

- panel abierto: cada `refreshSeconds` (default 4 s)
- tras cada acción: refresco inmediato
- `exitCode != 0` → daemon caído, se limpian los clientes

El socket `/run/user/1000/lan-mouse-socket.sock` expone eventos
(`FrontendEvent`) pero con protocolo **bincode**, no JSON, así que no se usa:
el polling del CLI es la única superficie estable.

## IPC propio

```
omarchy-shell shell toggle eztvn.lanmouse '{}'
omarchy-shell shell summon  eztvn.lanmouse '{}'
```

## Archivos

| Archivo | Rol |
|---------|-----|
| `manifest.json` | id, kinds, settings (`refreshSeconds`) |
| `Panel.qml` | raíz `Panel`: chip, estado, layout del panel |
| `LanMouseState.qml` | polling + cola de acciones CLI + fallback `config.toml` |
| `ArrangementCanvas.qml` | lienzo, tiles y resaltado de zona |
| `ArrangementTile.qml` | tile arrastrable con snap a borde |
| `ClientRow.qml` | endpoint + punto de estado + toggle `Cliente activo` |
| `SyncScreensRow.qml` | fila `Pantallas` → `apply-layout.sh` |
| `Model.js` | parseo, glifos/etiquetas, argv, layout y plan de sincronización |

## Limitaciones

- **Estado por polling**, no por eventos: hasta `refreshSeconds` de retraso si
  cambias la posición desde otra terminal.
- **Sin IPC hacia la laptop**: `lan-mouse` no expone el modo/resolución real
  del peer, así que el tile remoto usa **1920×1080 aproximado**.
- **Un solo cliente en el lienzo** (el primero de `cli list`); el estado
  soporta varios.
- **`save-config` es redundante en 0.11.0** (`set-position` ya persiste), pero
  se mantiene por si cambia el contrato.
- **Sincronizar pantallas** afecta solo los monitores locales; con un monitor
  es siempre no-op.

## Verificación

```bash
omarchy-qml-lint ~/.config/omarchy/plugins/eztvn.lanmouse/*.qml
node --test ~/.config/omarchy/plugins/eztvn.lanmouse/tests/
verify auto ~/.config/omarchy/plugins/eztvn.lanmouse
omarchy-shell shell ping
```
