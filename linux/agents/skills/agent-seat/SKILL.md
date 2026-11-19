---
name: agent-seat
description: "Interactuar con apps gráficas (click, tipeo, scroll, captura) sin tocar el cursor, el foco ni las ventanas del usuario: apps sandboxeadas en el asiento del agente, con puntero y teclado propios."
---

# Agent Seat

Usá el asiento cuando la tarea necesite una app gráfica de verdad: clickear una
página, llenar un formulario, ver cómo se renderiza una UI, usar una app que no
tiene CLI. El agente tiene puntero y teclado propios; el usuario sigue en su
workspace.

## Cuándo

- Interactuar con un navegador o una app nativa (click, tipeo, scroll, drag).
- Verificar algo que sólo se ve en pantalla y no alcanza con el DOM/CLI.
- Cuando abrir una ventana en la sesión del usuario lo interrumpiría.

Para pruebas web con Puppeteer/Playwright headless no hace falta; para evidencia
de UI usá `evidencia` (skill `evidencia`).

## Flujo

```bash
agent-seat run --cdp chromium https://example.com   # imprime el número de ventana
agent-seat state 1                                  # ¿dibujó? ¿popups? ¿quién actuó último?
agent-seat ui 1                                     # controles por rol y nombre
agent-seat click-ui 1 "button:Guardar"              # click por nombre, con tu puntero
agent-seat type 1 "hola" --key enter                # teclea en el layout del usuario
agent-seat screenshot 1 --output /tmp/seat.png      # sólo si no hay árbol
agent-seat stop                                     # cierra broker y sandboxes
```

## Reglas

- Leé `ui` antes de capturar: nombre, rol y posición cuestan cero imágenes.
- Después de actuar, releé `ui` y verificá el valor o estado; eso es la prueba.
- Capturá sólo si `ui` sale 2 (sin árbol), falta un control o hay que confirmar algo visual.
- Chromium/Electron: `run --cdp`, así `ui` lee la página por DevTools.
- El asiento es del agente, no del usuario: si él está escribiendo en una ventana del asiento, no toques esa ventana.
- El workspace del asiento es **20**; el atajo del usuario para saltar es `Super + Ctrl + Alt + X`.
- Nunca `ydotool`, `wtype`, `xdotool`, `grim` ni `wf-recorder` sobre la sesión del usuario.
- Login, captcha o 2FA: pedile al usuario que salte al asiento y lo haga él; esperá que termine.
- Los sandboxes comparten la red local (`--share-net`); no hay GPU; los logins persisten en `~/.local/state/omarchy/agent-seat/home`.
