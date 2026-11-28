# dsh-local-gamepad

Mando de Nintendo (Switch Pro Controller o Joy-Con por Bluetooth) como teclado
para la GUI web de DSH.

La regla del dueño: **las flechas del mando son exactamente las flechas del
teclado**. El plugin no navega la app por dentro: en cada pulsación emite un
`KeyboardEvent` real (`key`/`code` `"ArrowUp"`, `bubbles: true`,
`cancelable: true`) sobre `document.activeElement`, así responden los mismos
manejadores de teclado que con un teclado físico.

## Mapeo

| Mando | Tecla |
| --- | --- |
| D-pad 12/13/14/15 | `ArrowUp` / `ArrowDown` / `ArrowLeft` / `ArrowRight` |
| A (0) | `Enter` |
| B (1) | `Escape` |
| X (2) | `Backspace` |
| Y (3) | `Tab` |
| R1 / RB (5) | `Tab` |
| L1 / LB (4) | `Shift+Tab` |
| Start / + (9) | foco al compositor de DSH (solo fuera de un campo y sin diálogo/menú abierto) |
| Palanca izquierda (ejes 0/1) | flechas, con deadzone 0.35 |

Mantener pulsado repite cada 140 ms (como el auto-repeat del teclado).

## Decisión sobre inputs y límites del teclado sintético

Las flechas se emiten **también** dentro de `input`, `textarea` y
`contenteditable`: eso es lo que pidió el dueño. A/B/X/Y/Tab/Shift+Tab también
se emiten siempre.

Límite real del navegador: un `KeyboardEvent` creado con `dispatchEvent` no
dispara la acción por defecto (no es `isTrusted`). Los `keydown` llegan a los
manejadores de DSH —que es lo que navega la GUI, el composer Lexical y los
menús— pero en un `<input>`/`<textarea>` nativo el caret no se mueve solo, ni
Backspace borra, ni Tab salta el foco. El plugin no reimplementa el editor:
emite la misma tecla que el teclado y deja que DSH la interprete.

Start no emite `/`: un evento sintético no inserta texto, así que no abriría el
menú de comandos. En su lugar enfoca el compositor real
(`[data-composer-input]`), solo si el foco no está en un campo y no hay un
diálogo o menú abierto.

## Configuración sin tocar el repo

Desde la consola del navegador, antes de que cargue el plugin:

```js
window.__DSH_GAMEPAD_CONFIG__ = {
  deadzone: 0.5,
  repeatMs: 200,
  sticks: false,
  dpad: { 12: null },      // apaga el botón 12
  buttons: { 3: null },    // apaga Y
};
```

Mapeos extra también se pueden reemplazar:

```js
window.__DSH_GAMEPAD_CONFIG__ = {
  buttons: { 6: { key: "PageDown", code: "PageDown" } }, // ZL/R2
};
```

## Prueba

No hace falta mando físico: `tests/gamepad.test.mjs` reemplaza
`navigator.getGamepads()` por un mando falso, monta la mitad cliente y verifica
los eventos emitidos.

```sh
node --test tests/gamepad.test.mjs
```

Cubre: D-pad arriba → `keydown`/`keyup` `ArrowUp`; flechas en textarea; repeat
a 140 ms; A/B/X/Y/L1/R1/Start; Start no escribe `/` al tipear; deadzone de la
palanca; configuración; desconexión; desmontaje limpio.

## Límites reales

- Chromium/WebKit solo ven mandos que el sistema expone; en Linux hace falta
  que el mando esté emparejado por Bluetooth y visible en `/dev/input` (o por
  hidraw). Sin mando conectado, `navigator.getGamepads()` devuelve `null`.
- Los eventos son `isTrusted: false`. La UI de DSH los procesa porque escucha
  `keydown`/`keyup` normales; un handler que exija `isTrusted` no respondería.
- Se usa el primer mando conectado; un segundo mando se ignora.
- El plugin solo existe en el navegador: no agrega tools ni UI.
