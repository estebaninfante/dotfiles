---
name: omar-palabras
description: >
  Agregar, cambiar o depurar palabras clave de voz (hotwords) de Omar, el
  agente de voz local de esta máquina. Usala cuando el usuario pida "que cuando
  diga X haga Y", "agregá una palabra clave", "quiero decir play/enter/cerrar",
  o cuando una palabra clave no dispare, dispare de más, o haya que acotarla a
  una aplicación. Cubre el formato de ~/.local/share/omar/hotwords.json, el
  vocabulario cerrado de acciones, el alcance por ventana (`apps`), el guard de
  acciones destructivas y cómo probar sin micrófono. Triggers: hotword, palabra
  clave, comando de voz, "cuando diga", Omar, dictado, wake word.
---

# Agregar palabras clave a Omar

Las palabras clave (hotwords) son frases que se ejecutan **al oírlas**: sin decir
"Omar", sin conversación abierta, sin pasar por el router ni por ningún modelo.
Cero latencia: STT → acción.

## Dónde viven (y cuál tocar)

Hay cuatro lugares distintos para "una palabra que hace algo". Elegí bien:

| Qué querés | Dónde | Archivo |
| --- | --- | --- |
| Una orden suelta que diga y haga ya | **hotword** | `~/.local/share/omar/hotwords.json` |
| Que "Omar" te despierte | wake word | `~/.config/omar/config.json` → `wakeWord.word/words` |
| Navegar Vimium diciendo las teclas | **modo teclas** (estado) | `src/decide/keymode.ts` |
| Cerrar la conversación | end word | `config.json` → `conversation.endWords` |
| Corregir una frase que el agente entendió mal | regla aprendida | `omar teach "<frase>" <accion> ...` |

Si el usuario dice "quiero decir X y que pase Y" → **hotword**. Si es una frase
larga en lenguaje natural que necesita entender el contexto → va por el router o
el cerebro, no por acá.

## Formato

Archivo: `~/.local/share/omar/hotwords.json` (o `$OMAR_HOTWORDS`). Un array
de objetos. **Se relee en cada coincidencia: no hay que reiniciar nada.**

```json
[
  {
    "id": "guardar",
    "phrases": ["guarda el archivo", "guarda esto"],
    "apps": ["nvim", "kitty"],
    "actions": [{ "kind": "press_keys", "keys": "ctrl+s" }],
    "say": "",
    "note": "mismo id que la de fabrica: la reemplaza y queda acotada a kitty/nvim"
  }
]
```

- `id` (string, requerido): una entrada de usuario con el mismo `id` que una de
  fábrica **la reemplaza**. Con un `id` nuevo se **suma**: la de fábrica sigue
  existiendo y puede ganar fuera del `apps` de la tuya. Si querés cambiar el
  alcance de algo que ya existe, repetí el `id`.
- `phrases` (string[], requerido): se normalizan al comparar (minúsculas, sin
  acentos ni puntuación). Escribilas como las diría una persona.
- `actions` (Action[], requerido): vocabulario cerrado, abajo.
- `say` (string, opcional): confirmación hablada. `""` = silencio (recomendado
  para todo lo que se usa seguido).
- `apps` (string[], opcional): la hotword sólo vale en ventanas cuyo class o
  título **contenga** alguno de esos textos (sin distinguir mayúsculas). Sin
  `apps`, vale en todas.

## Cómo se decide qué gana

1. **Exacto o por prefijo.** `"sube el volumen"` matchea `"sube el volumen un
   poco"`. Por eso una frase corta puede comerse a una larga: si `"captura"` y
   `"captura de pantalla completa"` existen, la larga tiene que ir **antes** en
   el archivo (o en `phrases`) o nunca va a llegar.
2. **Dos pasadas**: primero las que declaran `apps`, después las generales. Una
   regla específica de una app gana sobre una general con la misma frase.
3. **El orden importa entre las de usuario**: las de usuario van antes que las de
   fábrica, y entre ellas gana la primera que matchea.
4. **Sin "Omar".** Se evalúan siempre, incluso con el micrófono en ambiente
   (tele, llamada, podcast). De ahí la regla siguiente.

## Modo teclas (Vimium): decir la tecla y que la pulse

`vimium` no es una hotword sino un **modo**, igual que `transcribe`: mientras
está prendido, cada frase se traduce a pulsaciones y no pasa por el router ni
por el modelo. Se apaga solo a los `keyMode.idleMs` (8 s) sin teclas o con
`corta vimium`.

```
"vimium"        -> modo ON (sólo en el navegador, `keyMode.apps`)
"efe"           -> pulsa F (Vimium muestra las etiquetas)
"a ese"         -> pulsa A y S (sigue la etiqueta "AS")
"as"            -> lo mismo: una etiqueta corta se parte en letras
"doble uve"     -> W
"uno"           -> 1
"enter"         -> Enter
"corta vimium"  -> modo OFF
```

- Acepta la letra pelada, el nombre español, los nombres de dos palabras y las
tecas de control. El relleno ("la tecla", "por favor") se ignora.
- Sólo escribe en el navegador: fuera de las apps de `keyMode.apps` el modo no
se prende y, si cambiás de ventana, las frases se ignoran.
- Seguridad: descarta bucles (`e, e, e, e`) y frases de más de 6 teclas; no se
aplica el filtro de baja confianza porque una letra suelta es corta por
naturaleza.
- Si el STT no te entiende una letra, decí **"tecla + letra"** ("tecla ese"):
el sesgo del decodificador está pensado para esa forma y para la letra pelada.
- Es excluyente con el dictado continuo: prender teclas apaga el dictado.
- Config: `keyMode.enabled`, `keyMode.apps`, `keyMode.idleMs`. Detalle completo
en `features/vimium-por-voz.md` y `scripts/verify/vimium-por-voz.mjs`.

## Seguridad: las destructivas no se disparan solas

`close_window` y `lock` **sólo se ejecutan dentro de la conversación** (después
de decir "Omar", o en un comando inline tipo "Omar, cerrar ventana"). En
ambiente se ignoran sin avisar. Está implementado en `src/voice/loop.ts` con
`isDestructiveAction()`; si agregás una acción nueva que destruye algo, sumala a
`DESTRUCTIVE_KINDS` en `src/decide/hotwords.ts`.

## Vocabulario cerrado de acciones

El modelo nunca inventa comandos: una hotword sólo puede producir estas acciones
(`src/core/types.ts`). Si la que necesitás no está, hay que agregarla al tipo
**y** al ejecutor (`src/act/desktop.ts`).

```
focus_window{match}            focus_direction{direction}
close_window{match?}           move_window_workspace{workspace,follow?,match?}
move_window_direction{direction}   resize_window{x,y}   swap_window{direction}
toggle_float                   fullscreen{action:"toggle"|"set"|"unset"}
focus_workspace{workspace}     cycle_workspace{delta}
list_windows{workspace?}       special_workspace{name,toggle?,move?}
move_workspace_to_monitor{monitor?}
launch{command}                type_text{text}        press_keys{keys}
mouse_move{x,y}                mouse_click{button}
clipboard_get                  clipboard_set{text}
volume{delta}                  mute                   brightness{delta}
expo_toggle                    screenshot{mode:"region"|"full"}
media{command:"play-pause"|"next"|"previous"}
lock                           notify{message,title?}
ui_read{app?,maxChars?}        ui_activate{match,app?}
ui_focus{match,app?}           ui_type{text,match?,app?}
browser_open{url?}             browser_click{target}  browser_type{text,target?,submit?}
browser_search{query}          browser_read{maxChars?} browser_scroll{delta}
browser_history{direction}     browser_press{keys}    browser_select{target,value}
browser_tabs
```

`press_keys` acepta `+` para combinar: `"ctrl+shift+z"`, `"ctrl+backspace"`.
Nombres de tecla: `enter tab escape space backspace delete insert up down left
right home end prior next f1..f12` y cualquier letra. Modificadores: `ctrl
shift alt super`.

## Probar sin micrófono (siempre hacelo antes de decir que quedó)

```bash
# 1. sintetizar la frase
espeak-ng -v es -w /tmp/t.wav "pausa"

# 2. replay por el loop, sin ejecutar nada
cd ~/developing/omar
node dist/index.js listen --file /tmp/t.wav --no-wake --dry-run --no-tts --no-status --once
```

`--no-wake` simula "estás en conversación" (sirve para probar destructivas). Sin
`--no-wake` probás el camino **ambiente**: ahí `close_window`/`lock` tienen que
ignorarse.

Salida esperada: `palabra clave: <acción>` y `[agent] [dry-run] {"kind": ...}`.

## Verificar el repo

```bash
cd ~/developing/omar
node scripts/verify/palabras-por-ventana.mjs    # rápido
bash scripts/verify/run-all.sh                  # build + todos los verificadores
```

Si cambiás el código (no sólo el JSON), además: documentá la feature en
`features/`, agregá el chequeo al verificador y una entrada en `DECISIONS.md`.

## Errores comunes

- **Creer que tu regla reemplaza a la de fábrica sin repetir el `id`.** Si la de
  fábrica se llama `guardar` y la tuya `guardar-nvim`, en la app que no está en
  tu `apps` sigue ganando la de fábrica. Para pisarla, mismo `id`.
- **Frase demasiado común** ("sí", "ok", "listo"): se dispara con cualquier cosa
  que diga la tele. Las frases tienen que ser explícitas.
- **Olvidar el prefijo**: `"corta"` también matchea `"corta esto"`. Es cómodo, pero
  significa que la frase corta tapa a cualquier cosa que empiece igual.
- **Poner la frase larga después de la corta**: nunca se alcanza.
- **Acción inexistente**: el plan falla en ejecución. Verificá contra la lista.
- **`press_keys` con nombres inventados**: no es lenguaje natural, es la tabla de
  arriba.
- **Confundir con el dictado**: `transcribe` / `fuera transcribe` son estado del
  loop y se evalúan **antes** que las hotwords. `"corta transcribe"` gana sobre
  `"corta"`.
- **Esperar que funcione con un solo gesto**: si el micrófono está ocupado por un
  dictado (`dictate.pid`), el loop se aparta y no evalúa nada.

## Dónde está implementado

- `src/decide/hotwords.ts` — matcher, built-ins, `apps`, `DESTRUCTIVE_KINDS`.
- `src/voice/loop.ts` — `hotwordTurn()`: dictado → hotword → contexto de ventana.
- `src/act/desktop.ts` — ejecutores (`press_keys`, `media`, `screenshot`, ...).
- `features/palabras-por-ventana.md` — criterios de aceptación.
- `scripts/verify/palabras-por-ventana.mjs` — verificador determinista.
