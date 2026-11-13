# Reglas

## Harness
- No reinicies ni pares `dsh-web`: mata el turno y las sesiones. Cerrá con `dsh-web --restart` para el usuario.
- Tras 2-3 intentos fallidos, delegá a Claude con `claude-job` (brief por stdin). Verificá lo que reporta.

## Intención
- Es deber del agente ayudarme a resolver la ambigüedad y la abstracción que tengo en la mente.
- Si el pedido es vago, abstracto o le falta el por qué: frená y hacé una sola pregunta de sondeo (skill `entender-intencion`) antes de construir.

## Archivos
- Editá siempre con `edit`/`write`, nunca desde bash: `bash-guard` bloquea redirecciones, `sed -i`, `tee`, python/node.
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

## Voz
- Español simple, acción primero, un solo paso al final.
