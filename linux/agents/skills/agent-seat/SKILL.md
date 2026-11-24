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
agent-seat run --tarea "comparar precios de vuelos" chromium https://example.com   # imprime N
agent-seat tarea 1 "revisar el checkout de la tienda"   # cuando cambia lo que hacés
agent-seat state 1                                  # ¿dibujó? ¿popups? ¿quién actuó último?
agent-seat ui 1                                     # controles por rol y nombre
agent-seat click-ui 1 "button:Guardar"              # click por nombre, con tu puntero
agent-seat type 1 "hola" --key enter                # teclea en el layout del usuario
agent-seat screenshot 1 --output /tmp/seat.png      # sólo si no hay árbol
agent-seat stop                                     # cierra broker y sandboxes
```

## Reglas

- Leé `ui` antes de capturar: nombre, rol y posición cuestan cero imágenes.
- Cuando terminás el trabajo, `agent-seat stop`: el asiento no se queda abierto ocupando RAM.
- Si te olvidás, el harness cierra el asiento al terminar el turno (plugin `seat-cierre`) y el vigía lo baja a los 5 min sin uso (`AGENT_SEAT_IDLE_CIERRE`).
- Después de actuar, releé `ui` y verificá el valor o estado; eso es la prueba.
- Capturá sólo si `ui` sale 2 (sin árbol), falta un control o hay que confirmar algo visual.
- `--tarea` obligatoria y concreta: **qué estás haciendo y sobre qué**, 3-6 palabras, en castellano ("comparar precios de vuelos", "revisar el checkout de la tienda").
- Prohibido texto genérico o en inglés ("present task", "testing", "probar cosas"): el usuario lee `▸ <agente> · <tarea>` en el tile y no sabe qué ventana es ni qué estás haciendo.
- Cuando cambia lo que estás haciendo, `agent-seat tarea N "…"` en el momento: el tile se renombra en ~1s.
- Sin `--tarea` el tile cae a tu última acción ("clic en «Llamada»") y, si no hubo, al nombre de la app: es el piso, no el objetivo.
- Navegadores: si ya hay uno abierto en el asiento, `run` abre tu URL como pestaña nueva ahí y devuelve esa ventana (no se lanza un segundo navegador: chocarían por el perfil). `--cdp` se agrega solo.
- El asiento es del agente, no del usuario: si él está escribiendo en una ventana del asiento, no toques esa ventana.
- El workspace del asiento es **20**; el atajo del usuario para saltar es `Super + Ctrl + Alt + X`.
- Nunca `ydotool`, `wtype`, `xdotool`, `grim` ni `wf-recorder` sobre la sesión del usuario.
- Login, captcha o 2FA: pedile al usuario que salte al asiento y lo haga él; esperá que termine.
- Los sandboxes comparten la red local (`--share-net`); no hay GPU; los logins persisten en `~/.local/state/omarchy/agent-seat/home`.
- Para mostrar cómo se ve el tile en la grilla sin capturar la pantalla del usuario ni abrir el overview: `agent-seat-tile [<ventana>]`. Compone la miniatura (borde naranja + la misma pestaña del overview) desde la captura del asiento.
- El usuario ve las ventanas como tiles en el overview (slots 11..16, pestaña arriba a la izquierda `▸ <agente> · <tarea o última acción>`): un tile por ventana, grilla dinámica.
