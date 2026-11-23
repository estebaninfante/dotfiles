---
name: evidencia
description: "Producir evidencia visual de una tarea (capturas, pasos, GIF, video, comparación antes/después) leyendo una sola hoja de contactos en vez de N imágenes."
---

# Evidencia visual

Toda prueba de UI termina con una prueba que se puede ver. Esta skill arma esa
prueba gastando pocos tokens: los pasos son silenciosos y al final se lee **una**
hoja de contactos.

## Cuándo

- Cualquier cambio que "se vea en pantalla": UI, layouts, estados, animaciones.
- Antes/después de un fix visual.
- Secuencias de varios pasos (login, formulario, navegación).

## Flujo

```bash
evidencia iniciar --nombre mi-prueba     # detecta la ventana del asiento
evidencia paso "estado inicial"          # silencioso si sale bien
evidencia paso "click en Guardar"
evidencia cerrar                         # imprime gif= y hoja=
```

- Leé **sólo la hoja de contactos**. El GIF es para que lo mire el usuario.
- Guardá el GIF/video como prueba de la tarea; la hoja es para que la leas vos.

## Grabar una secuencia

```bash
# muestrea frames del asiento mientras corre el comando
evidencia grabar --fps 4 --max 20 -- ./mi-script.sh
```

- `grabar` sirve para el asiento (ventana oculta): muestrea capturas del asiento.

## Antes/después

```bash
evidencia comparar antes.png despues.png --etiquetas "antes,después"
```

Devuelve una sola imagen lado a lado, con etiquetas, para mostrar el cambio.

## Reglas

- El objetivo se detecta solo: la ventana del asiento más nueva.
- `--asiento N` lo fijan a mano.
- `agent-seat screenshot` sólo escribe bajo el directorio actual; `evidencia` ya lo resuelve.
- Salidas en `~/Imágenes/screenshots/` (`EVIDENCIA_SALIDA` para cambiarlo).
- No leas capturas sueltas si podés leer la hoja: cuesta una imagen, no N.

## Automejora

Si tuviste que improvisar algo que esta skill no cubría, agregá **una** regla
atómica y publicá:

```bash
evidencia skill "wf-recorder graba sólo salidas montadas; el asiento usa frames"
~/dotfiles/scripts/dotfiles-sync.sh --force
```

- Una idea por línea, sin explicar lo obvio.
- La regla va abajo, en `## Aprendido`, con fecha automática.
- Si la regla contradice a otra, borrá la vieja en el mismo cambio.

## Aprendido
- 2026-11-19 — wf-recorder graba salidas montadas; el asiento vive en una ventana oculta y se muestrea con grabar
- 2026-11-23 — El --asiento de iniciar no persiste en los pasos: exportá OBJETIVO=asiento:N en cada invocación
