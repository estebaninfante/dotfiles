# Reglas

## Harness
- No reinicies ni pares `dsh-web`: mata el turno y las sesiones. Cerrá con `dsh-web --restart` para el usuario.
- Tras 2-3 intentos fallidos, escalá a un modelo superior con `codex-job` (brief por stdin; skill `escalar-a-modelo-superior`). Verificá lo que reporta.

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
- El número de tareas sale del contenido, no de la numeración del usuario: una falla o resultado verificable por tarea.
- Antes de planear, reescribí el pedido como resultados verificables; si la prueba de uno no prueba el otro, son dos tareas.
- Dos quejas que se arreglan con el mismo cambio van en una sola tarea.
- Un pedido que llega a mitad del turno con otra falla abre tarea nueva, no se cuela en la abierta.
- Prohibido: estimar tiempo, resumen de 4 puntos, inventar tareas.
- Una tarea por vez. Cerrá con qué quedó y qué sigue.

## Webapps
- Dejá `.webapp.json` y corré `webapp-launch <dir> --install`; `Exec` con ruta absoluta.
- No habilites servicios sin que el usuario lo pida.

## UI
- Antes de construir o refactorizar UI: `machine vicio`. Son los vicios reales del modelo, con evidencia. Leelos todos.
- Prohibido: `prompt()`/`alert()`/`confirm()`, pastillas de color para estado, puntos con halo o pulso, bordes punteados, tipografía display de carácter, más de 400 líneas por archivo.
- Estado: texto plano, no pastilla. Botones de una sola altura, con `:hover` y `:focus-visible`.
- Botones: ícono antes que texto; el texto sólo cuando el ícono no alcanza (regla del dueño, 2026-11-24).
- Antes de decir "listo": `npx impeccable detect <url-o-dir>` y captura a 390 y 1440 px.
- Lienzo Creativo (`~/Proyectos/lienzo-creativo`): `webapp-launch ~/Proyectos/lienzo-creativo`.

## Agent Seat (GUI y capturas)
- Para abrir una app gráfica, clickear, tipear o scrollear: `agent-seat` (skill `agent-seat`). Corre sandboxeado, en su workspace (20), con puntero y teclado propios.
- Al abrir una ventana del asiento, `--tarea` concreta (qué hacés y sobre qué, en castellano): es lo que el usuario lee en el tile del overview.
- Capturas de una ventana: `agent-seat screenshot`; secuencias y pruebas: `evidencia` (skill `evidencia`).
- Prohibido `ydotool`, `wtype`, `xdotool`, `grim` y `wf-recorder` sobre la sesión del usuario.
- Login, captcha o 2FA: pedile al usuario que salte con `Super + Ctrl + Alt + X` y esperá.
- Mientras el usuario escribe en una ventana del asiento, no toques esa ventana.
- Al terminar, `agent-seat stop`: el asiento y sus ventanas no quedan chupando RAM.
- Si te olvidás, el harness lo cierra al terminar el turno (plugin `seat-cierre`); el vigía, a los 5 min sin uso.

## Pruebas con ventanas
- Las ventanas de prueba van al asiento del agente; nunca a las pantallas del usuario.
- Prohibido manejar la ventana de una app del usuario: ni CDP/puppeteer sobre su sesión, ni clicks, ni teclas, ni navegarla, ni matarla para “probar”. Si hay que probar UI, abrí una ventana propia en el asiento (`agent-seat run …`) y capturá ahí.
- Si la app del usuario necesita reiniciarse para tomar un cambio, no la reinicies vos: dejá el build listo y decile qué reiniciar.
- Evidencia de UI: `evidencia iniciar/paso/cerrar` o `evidencia grabar -- <comando>`.

## Evidencia
- Para varios pasos usá `evidencia`: `evidencia iniciar`, `evidencia paso "…"` (silencioso), `evidencia cerrar` → imprime `gif=` y `hoja=`.
- Leé **solo la hoja de contactos**, no cada captura: una imagen en vez de N.
- Secuencia completa en una sola llamada: `evidencia grabar -- <comando>` → video + gif + hoja.
- Antes/después en una imagen: `evidencia comparar antes.png despues.png --etiquetas "antes,después"`.
- Detecta solo el objetivo: la ventana del asiento más nueva.
- Si la skill no cubría el caso: `evidencia skill "regla atómica"` y publicá dotfiles.

## Voz
- Español simple, acción primero, un solo paso al final.
