---
name: openagents-paralelo
description: Reparte cambios de UI de openagents (parte de LibreOS; el código vive en ~/developing/pi-desktop) entre varias sesiones de pi en paralelo. Usala cuando el usuario dicte cambios de interfaz de openagents y quiera velocidad, cuando haya que decidir si un pedido va a un agente que ya tiene contexto o a uno nuevo, o cuando haya que crear, mirar, manejar o cerrar esos agentes.
---

# Agentes en paralelo para openagents

El usuario está construyendo **LibreOS**, un sistema operativo, y **openagents**
es una parte de su plataforma. El código de esa parte vive hoy en
`~/developing/pi-desktop` (el nombre visible es openagents: `pi-desktop` es el
nombre interno del binario, no el producto). El usuario dicta los cambios de a
uno y quiere que se hagan en paralelo, en sesiones de pi visibles, sin perder el
foco ni esperar colas. Vos sos el **clasificador**: decidís si el
pedido lo sigue un agente que ya tiene contexto de esa zona, o si nace un
agente nuevo. La herramienta es `oa-agent`.

Ojo: en `~/developing/pi-desktop` trabajan **otros agentes** a la vez. No
renombres ni muevas esa carpeta sin avisarles: rompe sus sesiones.

## Ciclo por pedido

1. **Clasificar.** Mirá la tabla de agentes vivos:
   `oa-agent listar` (columnas: agente, workspace, tmux, ruta, vista, tema).
   - Si algún agente ya trabajó esa misma zona de la UI (misma vista, mismo
     archivo, mismo tema), mandale el pedido **a ese**.
   - Si no, `oa-agent nuevo <slug> "<tema>"` con un slug corto y en kebab-case
     que describa la zona (ej. `barra-compacta`, `grilla-agentes`).
   El tema del agente es su memoria: escribilo pensando en el próximo pedido.
   Al nacer, `oa-agent nuevo` enciende la **vista en vivo** del worktree (Vite
   con HMR) y la registra para el tablero `/vivo` de openagents. `OA_VIVO=0`
   desactiva ese encendido automático.
2. **Enviar el encargo**: `oa-agent enviar <slug> "<pedido>"`. Escribí el pedido
   completo y en imperativo: el agente no ve esta conversación. El comando le
   agrega solo la instrucción de dejar la marca al terminar.
3. **Esperar**: `oa-agent esperar <slug> 900`. Termina cuando aparece la marca
   `<agente>.txt`, e imprime el estado (`ok`/`error`), el resumen y el
   `git status` del worktree. Si no hay marca en el plazo, `oa-agent estado
   <slug>` muestra la pantalla y decime que se colgó.
4. **Verificar antes de dar por bueno**: entrá al worktree del agente (la ruta
   está en `oa-agent listar`, columna RUTA) y corré `scripts/verify/run-all.sh`.
   Leé el `git diff`. Sin verificación verde el cambio no está listo.
5. **Subir**: commit en la rama `agente/<slug>` dentro del worktree. El push
   necesita un remoto que **todavía no existe**: pedile al usuario a qué repo
   subirlo la primera vez. Después de subir, `oa-agent cerrar <slug>`.

## Reglas duras

- **Nunca le robes el foco.** `oa-agent` ya crea la ventana en un workspace que
  no es el activo, ni el 9, con `no_focus` y `suppress_event = activate`. No
  uses `hyprctl dispatch` para cambiar de workspace, ni abras ventanas a mano
  sin esa regla.
- **Un agente, un worktree.** Nunca trabajes sobre `~/developing/pi-desktop`
  (esa copia es de `main`): todo pasa en el worktree del agente.
- **La app openagents se abre en el workspace 5** (regla en
  `~/.config/hypr/windowrules.lua`, clase `pi-desktop`). Las sesiones de
  trabajo van en los workspaces 1, 3, 5, 8 y 10, máximo dos por workspace.
- **Un pedido, un encargo.** No mezcles dos cambios distintos en el mismo
  mensaje: cada uno va a su agente, y si es zona nueva, a su worktree.

## Referencia

`oa-agent` vive en `~/.local/bin/oa-agent`; el registro de agentes, en
`~/.local/share/openagents-agents/agentes.tsv` (agente, workspace, sesión tmux,
worktree, rama, tema), y las marcas de fin de encargo, en
`.../openagents-agents/marcas/<agente>.txt`.

| Comando | Para qué |
| --- | --- |
| `oa-agent listar` | tabla de agentes vivos |
| `oa-agent nuevo <slug> "<tema>"` | worktree + rama + tmux + ventana en un workspace libre |
| `oa-agent enviar <slug> "<pedido>"` | manda el pedido a la sesión de pi |
| `oa-agent esperar <slug> [seg]` | espera la marca y muestra resumen + `git status` |
| `oa-agent estado <slug>` | si trabaja o está libre, y las últimas líneas |
| `oa-agent vivo <slug>` | levanta la vista en vivo (Vite + HMR) del worktree |
| `oa-agent apagar <slug>` | apaga solo la vista en vivo |
| `oa-agent cerrar <slug>` | cierra ventana, tmux, worktree y rama |
| `oa-agent adoptar <slug> <ws> "<tema>"` | registra una sesión ya existente |

### Vistas en vivo

El tablero **`/vivo`** de openagents (botón de monitor en la barra) muestra un
iframe por agente encendido: los cambios de cada worktree se ven en tiempo real
con HMR, sin recargar ni reabrir la app. La API la sigue atendiendo la app real;
Vite le hace proxy (`PI_API_PORT`, por defecto 7717). Un worktree anterior a
esta feature (sin `PI_UI_PREVIEW` en `hooks.server.ts`) necesita `git -C
<worktree> merge main` para poder previsualizarse. Si cambiás el binario de la
app, hay que reiniciarla una vez para que exista `/api/vivo`.

El usuario ve cada sesión en su ventana de kitty: puede leerla, hablarle y
corregirla. Si corrige algo ahí, esa corrección es la verdad: no la pises
mandando otro encargo sobre lo mismo.
