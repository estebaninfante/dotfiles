---
name: browser-bench
description: Benchmark determinista y token-efficient de backends de browser-agent. Compara agent-browser, browser-control, brave-mcp, chrome-devtools-mcp, playwright-mcp y stagehand midiendo success, time_to_first_useful_state, roundtrips, tokens, fiabilidad, perfil real autenticado y descubrimiento en páginas desconocidas; produce SCORES.md y RANKING.md. Usar cuando pidan comparar/medir/iterar backends de browser agent, "cuál es mejor", eficiencia, tokens o elegir backend por tipo de página. Triggers: browser bench, benchmark browser, comparar browser agent, medir tokens navegador, ranking browser.
---

# browser-bench

Mide objetivamente qué backend de browser-agent conviene, con scorer determinista y veredicto
de un agente Scorer estricto independiente. El razonamiento vive en `bench/`; el modelo solo lee
el resultado compacto.

## Métricas (contrato)

Por cada (backend, escenario) se emite un registro JSON con:

- `success` (bool): se cumplió la aserción del escenario.
- `t_first_useful_ms`: tiempo hasta el primer estado útil (rapidez percibida).
- `total_ms`: tiempo total del escenario.
- `roundtrips`: nº de invocaciones al backend (latencia de agente; cada una = espera + tokens).
- `snapshot_chars` / `est_tokens`: texto que el agente debe leer. `est_tokens = ceil(chars/4)`.
  Incluye el programa/JS que el adapter escribió (contabilidad del trabajo del agente).
- `error`, `detail`, `data`, `ts`.

`score.mjs` agrega: fiabilidad = aciertos/intentos (sobre TODAS las filas, sin dedupe por último
ts); `tokens` en escala log absoluta (no min-max); `realProfile` MEDIDO = pass de `auth_roundtrip`
(no el bool declarado); `ext` peso .05 hasta ejercitarlo; `total = raw * fiabilidad`. Los
escenarios `bestEffort` (red externa anti-bot, p.ej. YouTube) se cuentan en fiabilidad y además
se reportan aparte para transparencia.

## Uso

```bash
cd ~/.config/opencode/skills/browser-bench/bench
node run.mjs                                   # 6 adapters x escenarios x1
node run.mjs --repeat 3 --results results-rN.json   # fiabilidad (3 reps/escenario)
node run.mjs --adapter browser-control --scenario explore
node score.mjs results-rN.json                 # escribe ../SCORES.md (+ RANKING a mano)
```

Salida: tabla por stdout + JSON de resultados + recordatorio de actualizar docs.

## Escenarios

- `public_nav`: example.com -> título/texto. (No tiene H1.)
- `youtube_light`: YouTube -> buscar "open source" -> >=3 títulos.
- `explore`: news.ycombinator.com -> >=12 items de un outline GENÉRICO (headings + interactivos),
  sin selectores por página. Mide costo de ENTENDER una página desconocida.
- `explore2`: react.dev/learn, mismo extractor => prueba genericidad (no overfit).
- `auth_roundtrip`: servidor local propio (benigno, NO toca cuentas del usuario). Login con cookie
  -> REINICIO COMPLETO del navegador con el mismo perfil persistente -> relectura del secreto.
  Mide persistencia REAL de sesión.
- `spa_task`: SPA local determinista (click -> aparecen items).

Timeout por intento: 90s. Sin cuentas privadas.

## Agentes / scorer

- Agente dueño del dominio: `browser-pilot` (~/.config/opencode/agents/browser-pilot.md).
- Agente Scorer estricto: `browser-scorer` (rúbrica propia, veredicto independiente). Requiere
  reiniciar opencode para estar disponible como subagent_type.

## Reglas

- Determinista y repetible: mismo comando, mismo escenario.
- Nunca screenshots como fuente primaria (solo si un escenario lo exige).
- Todo local; no exfiltrar cookies/credenciales. NO loguear/automatizar Meta/WhatsApp/Clerk.
- Actualizar `SCORES.md` (automático), `RANKING.md` y `RESEARCH.md` tras cada corrida relevante.
- Sin comentarios en el código (regla dura del host).

## Gotchas de backends (aprendidos)

- **agent-browser**: chromium **headless** por defecto, `user-data-dir` en `/tmp` (NO perfil real).
  Perfil real = `--profile Default` (copia read-only; auth imposible persistir). Dispatcher debe
  rutear `explore*` (bug histórico: la función existía pero el dispatcher no la llamaba).
- **browser-control**: requiere relay + extensión MV3 adjunta. Aislado:
  `P=$(npm root -g)/@opencode-ai/browser-control/extension/dist; setsid chromium --headless=new
  --user-data-dir=/tmp/bc-profile --load-extension=$P --disable-extensions-except=$P about:blank`.
  Adapter borra `BROWSER_CONTROL_SESSION` (una sesión inexistente da `Session not found`).
  El código de `execute` corre en contexto Node/Playwright: usar `page.$eval`/`page.$$eval`.
  **YouTube flaky bajo harness** (pestañas residuales del navegador persistente + lazy-render);
  aislado funciona. Arreglar con contexto fresco por escenario.
- **`close --all` al inicio de un escenario es race**: limpiar sesiones UNA vez antes de la corrida.
- **`return fn()` async dentro de `try/finally`**: el `finally` corre antes de resolver la promesa.
  Usar `return await fn()`.
- Refs `@eN` de `agent-browser snapshot` solo valen mientras viva el browser/tab.
- YouTube: buscador `combobox "Search"` (ref vía `snapshot -i`); títulos con `a#video-title`.

## Archivos

- `bench/run.mjs` — harness (adapters + scenarios + servidor local + métricas).
- `bench/score.mjs` / `bench/capabilities.mjs` — scorer determinista -> `SCORES.md`.
- `bench/server.mjs` — endpoints locales `/login`, `/secret`, `/app` (auth + SPA deterministas).
- `bench/adapters/*.mjs` — un adapter por backend (contrato `available()` / `runScenario()`).
- `bench/mcp/client.mjs`, `bench/mcp/list.mjs` — cliente MCP stdio genérico.
- `RESEARCH.md` — tabla FASE 0 (candidatos y estado de repos).
- `RANKING.md` — ranking vivo, veredicto del scorer, defaults por tipo de página.
- `SCORES.md` — scores numerados de la última corrida.
