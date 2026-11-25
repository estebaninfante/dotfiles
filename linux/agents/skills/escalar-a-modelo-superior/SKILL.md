---
name: escalar-a-modelo-superior
description: 'Se trabó tras 2-3 intentos o el usuario dice "probá con otro modelo": escalá a Codex, Claude u opencode con `*-job`.'
---
# Escalar a un modelo con más razonamiento

Un modelo no "siente" cuál es mejor: la escalera está escrita acá y se comprueba en disco.

## La escalera (arriba primero; se usa la primera que responda)

| Motor | Comprobación | Lanzador |
|---|---|---|
| Codex (ChatGPT, el que pagás) | `codex login status \| grep -q ChatGPT` | `$HOME/.local/bin/codex-job` |
| Claude Code | `claude auth status \| grep -q '"loggedIn": true'` | `$HOME/.local/bin/claude-job` |
| opencode (su propio presupuesto) | `opencode auth list \| grep -q stored` | `$HOME/.local/bin/opencode-job -m <modelo>` |

`opencode-job` sin `-m` usa `opencode-go/gpt-6-luna`. Otros altos de esa cuenta: `gemini-4-argon`, `glm-5.3`, `grok-4.7`.

## Cuándo escalar

- El mismo síntoma sigue después de 2 o 3 intentos serios (no de 10 variaciones).
- Cada arreglo rompe otra cosa.
- Estás probando a ciegas (rebuild + reinicio) en vez de instrumentar y medir.

No escales tareas de un paso ni cosas que ya sabés hacer.

## Cómo

1. Brief por **stdin**, como trabajo en segundo plano (`run_in_background: true`): la fila del job se abre en el hilo y muestra `DICE:` (texto), `HACE:` (cada paso) y `FIN:` (cierre).
   ```bash
   codex-job <<'BRIEF'
   …
   BRIEF
   ```
2. El brief lleva: el problema en una línea, **las variantes ya probadas y qué pasó con cada una**, rutas y comandos de verificación, y qué no se puede romper.
3. Las reglas del delegado van dentro del brief: **no delegar de nuevo** (un `*-job` dentro de otro `*-job` choca con el sandbox y pierde el turno), no reiniciar `:3980` (`dsh-web`), no publicar en git, nada de `rm -rf` fuera de `/tmp`.
4. Si el motor de arriba no responde, bajá un peldaño. Nunca dos motores a la vez sobre el mismo síntoma.

## Después

1. Leé el `FIN:`.
2. Verificá vos lo que dice (captura, `curl`, `node --check`): también se equivoca.
3. Pasale al usuario qué cambió, con qué prueba, y qué queda de su lado.
