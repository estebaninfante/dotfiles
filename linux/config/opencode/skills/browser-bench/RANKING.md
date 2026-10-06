# RANKING — browser-agent backends

Actualizar tras cada corrida con `bench/run.mjs` + `bench/score.mjs`. No editar números a mano.

## Ganador (r8, canónico, honesto)

**browser-control** = 6.2/10 (raw 7.5, fiabilidad 0.83). Mejor del set por amplio margen y el
único con `realProfile` MEDIDO (persistencia de sesión real). Ningún backend supera 8 con rúbrica
honesta: es el techo *estructural del benchmark* (ver Veredicto).

Dataset: `bench/results-r8.json` — 6 backends x 6 escenarios x 3 repeticiones = 18 intentos c/u.

## Scores medidos (r8)

| Backend | TOTAL | raw | fiab | avg_tokens | avg_t_first_ms | avg_rt |
|---|---|---|---|---|---|---|
| browser-control | **6.2** | 7.5 | 0.83 | 357 | 3401 | 1.3 |
| stagehand | 5.2 | 6.2 | 0.83 | 252 | 2350 | 0 |
| chrome-devtools-mcp | 4.0 | 4.8 | 0.83 | 4542 | 3076 | 3.5 |
| brave-mcp | 3.4 | 4.1 | 0.83 | 4484 | 3620 | 3.5 |
| agent-browser | 3.3 | 3.9 | 0.83 | 926 | 4158 | 6.2 |
| playwright-mcp | 3.1 | 3.7 | 0.83 | 4283 | 4250 | 2.8 |

Pesos (score.mjs): tokens .25 (escala log absoluta), speed .20, roundtrips .10, realProfile .15,
goal .15, ext .05, maint .05. `total = raw * fiabilidad`.

## Fixes de honestidad aplicados en r8 (pedidos por el Scorer)

1. **YouTube devuelto al denominador** de fiabilidad (ya no best-effort): browser-control 0/3 por
   anti-bot de YouTube sobre perfil persistente. Se reporta aparte, pero cuenta. Fiabilidad 0.83.
2. **realProfile MEDIDO, no declarado**: el score usa el pass de `auth_roundtrip` (no el bool de
   capabilities). Los 5 que no persisten obtienen 0 aunque se declaren realProfile.
3. **ext peso .10 -> .05** hasta ejercitarlo (network/secrets/recording), para no regalar peso.
4. **Tokens de browser-control incluyen su payload devuelto** (antes solo contaba el programa).

## Veredicto honesto

- Ningún backend >8. browser-control ~7 raw; 6.2 con fiabilidad. Resto ≤5.2.
- 45% del raw es *declarado* (realProfile+goal+ext+maint); tokens no incluyen razonamiento LLM
  (adapters son scripted, no LLM-en-el-loop); `ext` sin ejercitar; YouTube anti-bot penaliza al
  perfil persistente. Con todo medido (LLM tokens + ext ejercitado + YouTube resuelto) el techo
  honesto de browser-control es ~8, no >8.

## Qué se midió y qué significa

Escenarios: `public_nav`, `youtube_light`, `explore` (HN, outline genérico), `explore2`
(react.dev/learn, mismo extractor => genericidad), `auth_roundtrip` (login local + reinicio
COMPLETO del navegador con perfil persistente + relectura => persistencia REAL),
`spa_task` (SPA local determinista: click -> items).

Hallazgos clave:
- **auth_roundtrip**: SOLO browser-control PASA (3/3). Los otros 5 usan perfil temporal/aislado.
  `realProfile` deja de ser un atributo declarado y pasa a estar medido.
- **explore/explore2**: el outline genérico por JS (browser-control) cuesta ~65-128 tok / 1 rt,
  frente a volcar el árbol a11y completo (agent-browser 3.4k, brave-mcp 9.8k, playwright 12k).
  Costo de "entender" una página desconocida = donde más se separan.
- **YouTube (anti-bot sobre perfil persistente)**: browser-control falla 0/3 de forma
  reproducible; los backends de navegador fresco/aislado pasan. Es un límite real del perfil
  persistente ante anti-bot externo, no un bug de selector (aislado devuelve 3 títulos).

## Defaults por tipo de página (medido)

- Público (nav simple): cualquier backend. Más barato: browser-control (1 execute) / agent-browser.
- Autenticado (perfil real con sesión): **browser-control** (único con persistencia medida).
- SPA con interacción: browser-control (1 execute multi-paso) > stagehand (local) > MCPs.
- Descubrir/mapear página desconocida: browser-control (outline JS, 1 rt) >> MCPs (a11y tree).
- Media (YouTube): agent-browser / MCPs hoy más estables; browser-control por arreglar.
- Casi tiempo-real (poll corto): browser-control (JS persistente por sesión).

## Extensibilidad / capacidades (cualitativo)

| Backend | Perfil real | Batch | Delta/diff | MCP | CLI | Multi-sesión | Dominios permitidos | Mantenido |
|---|---|---|---|---|---|---|---|---|
| browser-control | sí (extension MV3, persistencia medida) | JS arbitrario persistente | no | sí | sí | sí (relay) | — | activo 2026 |
| agent-browser | copia read-only (auth imposible) | sí (`batch`) | sí (`--delta`, `diff`) | sí | sí | sí (`--session`) | sí (`--allowed-domains`) | activo 2026 |
| brave-mcp | attach Brave real | no claro | no | sí | sí | — | — | activo 2026 (fork 28 stars) |
| chrome-devtools-mcp | condicional (`--browserUrl`) | no claro | no | sí | sí | — | — | Google official |
| stagehand | no (temp) | vía código | no | sí (CLI) | sí | sí | no directo | activo (act/extract requieren LLM key) |
| playwright-mcp | solo via extension/cdp | no claro | no | sí | sí | sí | — | Microsoft |

## Siguiente sesión (para subir el techo honesto)

1. **Contabilidad de tokens con LLM real**: medir input+razonamiento+output de un agente
   LLM-en-el-loop (hoy los adapters son scripted y solo cuentan superficie). Es el gap #1.
2. **Ejercitar `ext`** de browser-control (network/secrets/recording) con check determinista y
   subir su peso de vuelta a .10.
3. **YouTube para perfil persistente**: mitigar anti-bot de forma legítima (p.ej. espera
   adaptativa, rotación de pestaña) o aceptar que browser-control no sirve para media.
4. Solo entonces el scorer honesto podría firmar ~8. >8 exigiría que browser-control gane
   también en media y con tokens de razonamiento medidos.
