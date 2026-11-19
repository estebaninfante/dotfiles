# Reglas

## Harness
- No reinicies ni pares `dsh-web`: mata el turno y las sesiones. Cerrá con `dsh-web --restart` para el usuario.
- Tras 2-3 intentos fallidos, delegá a Claude con `claude-job` (brief por stdin). Verificá lo que reporta.

## Intención
- Es deber del agente ayudarme a resolver la ambigüedad y la abstracción que tengo en la mente.
- Si el pedido es vago, abstracto o le falta el por qué: frená y hacé las preguntas que hagan falta (una por vez) hasta que el objetivo esté claro (skill `entender-intencion`), antes de construir.

## Resolver
- Cuando algo se rompe: dame primero la solución que lo deje usable ya, y después la causa.

## Archivos
- Editá siempre con `edit`/`write`, nunca desde bash: `bash-guard` bloquea redirecciones, `sed -i`, `tee`, python/node.
- Si `bash-guard` te frena y no era una edición: decímelo, no lo rodees en silencio.
- Reintentá el comando con `DSH_GUARD_ALLOW=1` adelante solo con mi OK.
- Notas y reglas atómicas: una idea por línea, sin explicar lo obvio.

## Proyectos
- Proyecto = objetivo + tareas + la prueba.
- Capturá con nombre: `machine idea --title "…"`. A proyecto: `machine promote`.
- Preguntá en el modal (`ask_user_question`), nunca en texto.
- Las tareas las dice el usuario: pasos grandes ("construir la app"), no funcionalidades.
- Prohibido: estimar tiempo, resumen de 4 puntos, inventar tareas.
- Una tarea por vez. Cerrá con qué quedó y qué sigue.

## Webapps
- Dejá `.webapp.json` y corré `webapp-launch <dir> --install`; `Exec` con ruta absoluta.
- No habilites servicios sin que el usuario lo pida.

## UI
- Antes de construir o refactorizar UI: `machine vicio`. Son los vicios reales del modelo, con evidencia. Leelos todos.
- Prohibido: `prompt()`/`alert()`/`confirm()`, pastillas de color para estado, puntos con halo o pulso, bordes punteados, tipografía display de carácter, más de 400 líneas por archivo.
- Estado: texto plano, no pastilla. Botones de una sola altura, con `:hover` y `:focus-visible`.
- Antes de decir "listo": `npx impeccable detect <url-o-dir>` y captura a 390 y 1440 px.
- Lienzo Creativo (`~/Proyectos/lienzo-creativo`): `webapp-launch ~/Proyectos/lienzo-creativo`.

## Agent Seat (interactuar con GUI)
- Para abrir una app gráfica, clickear, tipear o scrollear: `agent-seat` (skill `agent-seat`). Corre sandboxeado, en su workspace (20), con puntero y teclado propios.
- `pantalla-agente abrir` NO se usa para apps: si el app-id llega tarde, la ventana aparece un instante en las pantallas del usuario. El asiento es el único camino para GUI.
- `pantalla-agente` queda sólo para capturas de pantalla completa sin abrir apps (`montar` + `capturar` + `desmontar`).
- Prohibido `ydotool`, `wtype`, `xdotool`, `grim` y `wf-recorder` sobre la sesión del usuario.
- Login, captcha o 2FA: pedile al usuario que salte con `Super + Ctrl + Alt + X` y esperá.
- Mientras el usuario escribe en una ventana del asiento, no toques esa ventana.

## Pruebas con ventanas
- Las ventanas de prueba nunca van en las pantallas del usuario: van al asiento del agente.
- Capturas de UI completas: `pantalla-agente montar`, `capturar`, `desmontar`; sin abrir apps ahí.

## Evidencia
- Para varios pasos usá `evidencia`: `evidencia iniciar`, `evidencia paso "…"` (silencioso), `evidencia cerrar` → imprime `gif=` y `hoja=`.
- Leé **solo la hoja de contactos**, no cada captura: una imagen en vez de N.
- Secuencia completa en una sola llamada: `evidencia grabar -- <comando>` → video + gif + hoja.
- Pantalla montada en tiempo real: `evidencia grabar-vivo -- <comando>` (wf-recorder); en el asiento cae a frames.
- Antes/después en una imagen: `evidencia comparar antes.png despues.png --etiquetas "antes,después"`.
- Detecta solo el objetivo: la ventana del asiento más nueva o la pantalla montada.
- Si la skill no cubría el caso: `evidencia skill "regla atómica"` y publicá dotfiles.

## Voz
- Español simple, acción primero, un solo paso al final.
