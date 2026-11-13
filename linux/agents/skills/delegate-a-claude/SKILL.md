---
name: delegate-a-claude
description: Delegar a Claude Code un problema trabado tras 2-3 intentos, o cuando el usuario dice 'probá con otro modelo'.
---
# Delegar a Claude Code (como subagente del hilo)

Claude corre **dentro de la conversación**, no en un panel ni con archivos de brief.
El usuario ve al delegado trabajar: su tarjeta queda en el hilo con el estado y los pasos.

## Cuándo delegar (y cuándo no)

Delegá cuando:

- El mismo síntoma sigue después de 2 o 3 intentos serios (no de 10 variaciones).
- Cada arreglo rompe otra cosa.
- El arreglo toca un binario/plugin y cada iteración cuesta caro.
- Estás probando a ciegas (rebuild + reinicio) en vez de instrumentar y medir.

No delegues tareas de un paso ni cosas que ya sabés hacer.

## Cómo (un solo camino)

1. Lanzá `claude-job` con el brief por **stdin** como **trabajo en segundo plano**
   (bash con `run_in_background: true`). La fila del job aparece arriba del hilo y su
   salida se puede abrir **mientras Claude trabaja**: `DICE:` (texto), `HACE:` (cada
   paso), `FIN:` (cierre). Eso es la delegación visible.
   ```bash
   claude-job <<'BRIEF'
   …brief…
   BRIEF
   ```
   No hay `brief.md`, ni `out.log`, ni estado en disco.

2. El brief tiene la misma forma de siempre:
   - el problema en una línea y el contexto de la máquina;
   - **las variantes ya probadas y qué pasó con cada una** (lo que más ahorra);
   - nombres y rutas reales, comandos de verificación;
   - qué no se puede romper y cómo se comprueba.

3. Cancelá la delegación cuando ya no haga falta; el subagente lo hace solo al
   terminar.

## Reglas del delegado (ponelas en el brief)

- **No reiniciar** `:3980` (`dsh-web`): mata la sesión del usuario. Para probar, una
  instancia desechable (`dsh --profile web --no-open --port 3998`).
- No publicar en git: hay otras sesiones sobre el repo; publica el agente que delega.
- Nada de `rm -rf` fuera de `/tmp`.

## Después

1. Leé el reporte del subagente.
2. **Verificá vos** lo que dice (captura, `curl`, `node --check`): también se equivoca.
3. Pasale al usuario: qué cambió, con qué evidencia, y qué queda de su lado.
