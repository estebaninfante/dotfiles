# SCORES — browser-agent backends

Generado por bench/score.mjs. Pesos: tokens=0.25, speed=0.2, roundtrips=0.1, realProfile=0.15, goal=0.15, ext=0.05, maint=0.05.
tokens = escala log absoluta = costo-a-goal (autoría del programa + payload leído). total = raw * fiabilidad(pass/intentos).
Fiabilidad = solo escenarios controlables; los marcados bestEffort (red externa, p.ej. YouTube anti-bot) se reportan aparte.

| Backend | TOTAL | raw | fiabilidad | intentos | tokens | speed | rt | realProf | goal | ext | maint |
|---|---|---|---|---|---|---|---|---|---|---|---|
| browser-control | **6.2** | 7.5 | 0.83 | 18 | 6.1 | 5 | 8.1 | 10 | 10 | 8 | 7 |
| stagehand | **5.2** | 6.2 | 0.83 | 18 | 6.5 | 10 | 6 | 0 | 6 | 8 | 8 |
| chrome-devtools-mcp | **4** | 4.8 | 0.83 | 18 | 3.4 | 6.6 | 4.9 | 0 | 7 | 9 | 9 |
| brave-mcp | **3.4** | 4.1 | 0.83 | 18 | 3.4 | 4 | 4.9 | 0 | 7 | 9 | 6 |
| agent-browser | **3.3** | 3.9 | 0.83 | 18 | 5.1 | 1.4 | 1 | 0 | 8 | 8 | 9 |
| playwright-mcp | **3.1** | 3.7 | 0.83 | 18 | 3.4 | 1 | 5.9 | 0 | 7 | 7 | 9 |

## Detalle medido

| Backend | avg_tokens | avg_t_first_ms | avg_roundtrips |
|---|---|---|---|
| browser-control | 357 | 3401 | 1.3 |
| stagehand | 252 | 2350 | 0 |
| chrome-devtools-mcp | 4542 | 3076 | 3.5 |
| brave-mcp | 4484 | 3620 | 3.5 |
| agent-browser | 926 | 4158 | 6.2 |
| playwright-mcp | 4283 | 4250 | 2.8 |

## Capacidades

- **browser-control**: execute() Playwright JS arbitrario, relay+sessions, network/secrets/recording, MCP+CLI
- **stagehand**: act/extract/observe self-healing requieren LLM key (no configurada) => goal capado a 6; SDK TS/Py/Go, local o Browserbase cloud. Medido solo page local.
- **chrome-devtools-mcp**: Google official, CDP, perf/red; attach via --browserUrl
- **brave-mcp**: devtools parity full (perf/red/heap/lighthouse), attach Brave real, 30 tools, CLI; fork 28 stars
- **agent-browser**: refs a11y, snapshot --delta, batch, profile copy read-only, MCP+CLI, allowed-domains
- **playwright-mcp**: a11y snapshot, trace; real profile solo via --extension/--cdp-endpoint

## Best-effort (red externa, fuera de fiabilidad)

| Backend | bestEffort_pass/intentos | rate |
|---|---|---|
| agent-browser | 3/3 | 1.00 |
| browser-control | 0/3 | 0.00 |
| brave-mcp | 3/3 | 1.00 |
| playwright-mcp | 3/3 | 1.00 |
| chrome-devtools-mcp | 3/3 | 1.00 |
| stagehand | 3/3 | 1.00 |
