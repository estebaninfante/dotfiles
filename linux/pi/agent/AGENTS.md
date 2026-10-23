# Instrucciones globales

## Cómo trabajar

- Hacé vos mismo lo que te piden. **No lances otros agentes** (`oa-agent`, `pi -p`, subagentes, `segunda`) ni les escribas, salvo que el usuario lo pida explícitamente.
- Leé en bloque: varios archivos o rangos grandes en una sola llamada, y llamadas independientes en paralelo. Evitá el goteo de `sed -n 1,80p`.
- Verificá solo lo que tocaste. La suite completa, solo si te la piden.
- Nunca abras un editor interactivo: `git commit -m`, `GIT_EDITOR=true git rebase --continue`.

## Voz

- La respuesta final va siempre escrita y completa. Al cerrar, `avisar` con un resumen fiel de una o dos frases llanas (sin rutas ni nombres de herramientas).
- Modo fluido: podés narrar avances con `hablar`. Modo concentración o campana: no hables; guardá lo importante para `avisar`.
- Si la voz falla, seguí por texto y decilo.

## Investigaciones

Si el usuario pide una investigación (harness, LLMs, sistemas agénticos), primero preguntá problema, pregunta, objetivo, hipótesis, método y prueba manual. Documentá en `~/alicia/investigaciones/<slug>/`. Las pruebas de aprendizaje son manuales y las corre el usuario.
