---
name: pantalla-agente
description: "Montar una pantalla headless invisible para probar apps o capturar sin interrumpir al usuario; se desmonta sola cuando queda ociosa."
---

# Pantalla de agentes

Probar UI no puede abrir ventanas en las pantallas del usuario. Montá una salida
virtual, probá ahí, capturá con grim y desmontala.

## Cuándo

Cualquier prueba que abra una ventana: webapps, capturas a 390 y 1440 px, apps
nativas, diálogos. Nunca en las pantallas del usuario, ni "un segundo".

## Flujo

```bash
pantalla-agente montar --tamano 1440x900      # salida AGENTE-1, invisible, en el espacio 12
pantalla-agente abrir --clase agente-test-ui -- foot -a agente-test-ui sh -c '…'
pantalla-agente capturar /tmp/shot.png       # PNG de la pantalla completa
pantalla-agente cerrar                       # cierra las ventanas de prueba
pantalla-agente desmontar
```

## Reglas

- `montar` sin `--tamano` da 1440x900. Poné el del caso: `--tamano 390x844` para mobile, `--transform 3` para vertical.
- El espacio es **fijo (12)** y `montar` lo muestra en la salida virtual; la regla estática de `windowrules.lua` manda ahí las clases `agente-test-*`, así la ventana nace oculta sin carrera.
- Por eso la clase tiene que empezar con `agente-test-`: `foot -a agente-test-ui …`, `chromium --class=agente-test-web …`, `kitty --class=agente-test-tui …`.
- `capturar` saca la salida entera. La barra de Omarchy ocupa 24 px arriba: recortá si el test es de contenido.
- Ventanas ya abiertas: `mover class:<clase>` (o `title:<regex>`, `address:0x…`). Nunca mover ventanas del usuario.
- Al terminar, `desmontar`. Si te olvidás, el watchdog la descuelga a los 10 min sin uso (`PANTALLA_AGENTE_TTL`).
- Si `estado` dice "no montada", montá de nuevo: la salida virtual no sobrevive un `hyprctl reload`.
- `desmontar` cierra las ventanas que quedaron en el espacio propio para que no salten a las pantallas del usuario; `--conservar` las deja (solo si el usuario quiere verlas).

## Evidencia (capturas, GIF, video)

`evidencia` junta varios pasos en un GIF y una hoja de contactos, para no leer N imágenes:

```bash
evidencia iniciar --nombre mi-prueba     # sesión; detecta la ventana del asiento o AGENTE-1
evidencia paso "estado inicial"          # silencioso si sale bien
evidencia paso "click en Guardar"
evidencia cerrar                         # imprime gif= y hoja=
evidencia grabar --fps 4 -- <comando>    # video + gif + hoja en una sola llamada
```

- Leé **sólo la hoja de contactos** que imprime `cerrar`; el GIF es para que lo mire el usuario.
- `--asiento N` o `--pantalla OUT` fijan el objetivo a mano; por defecto elige la ventana del asiento más nueva.
- `agent-seat screenshot` sólo escribe en su runtime o bajo el directorio actual: `evidencia` ya lo resuelve.
