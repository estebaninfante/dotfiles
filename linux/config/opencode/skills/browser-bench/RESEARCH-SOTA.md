# RESEARCH-SOTA — Control de navegador por agentes casi en tiempo real (2025–2026)

Investigación para el stack `browser-pilot` (Brave real + `browser-control` relay :19989 + extension MV3,
runner `lib/pilot.mjs`, memoria `selectors.json` / `playbooks/` / `runs.jsonl`).

Fecha de investigación: **2026-10-06**. Método: websearch + webfetch de fuentes primarias (docs Chrome,
arXiv, GitHub, docs de vendors) y el benchmark local `browser-bench/`. Las señales de X se obtuvieron vía
índice de búsqueda (URLs de estado de X); **no se pudo delegar a `browser-pilot`** porque esta sesión no
expone la tool `task` (ver §Huecos).

Leyenda: `[H]` hecho citado · `[I]` inferencia propia · `[S]` auto-publicado por vendor (cautela).

---

## TL;DR

1. El cuello de botella ya no es el navegador sino **la orquestación LLM**: en un loop de agente, 1 decisión
   = 1 round-trip. La palanca #1 en 2026 es **reemplazar el LLM en cada paso por batches y por un modelo de
   decisión pequeño (System One: Jev/Laya)**. Evidencia: `browser-use/jev-ultrafast` bajó la tarea de
   Google Flights de 9.45s a 7.09s (−25%) y las llamadas al protocolo de 1.092 a 101 (×10.8 menos) sin
   pantallazos en el loop por defecto [1].
2. **Batch de acciones** en un solo tool-call es la optimización más barata: en un formulario de 28 campos,
   batching dio −74% tool calls, −57% tiempo (104.5s vs 245.1s) y −41% tokens [2].
3. **Ver la página**: a11y tree es 2–4× más rápido por paso que screenshots (50–200ms extracción vs 4–10s
   ciclo visión), pero árboles completos son caros (3.4k–12k tok en nuestro bench; el paper reporta miles de
   tokens extra por paso) [3][4][5][6]. Un **outline JS selectivo/diff** es lo más barato (nuestro bench:
   65–128 tok / 1 round-trip).
4. **WebMCP** (estándar W3C propuesto por Google+Microsoft) es la apuesta estructural: herramientas tipadas
   de la página invocadas "casi instantáneas, sin round-trip a servidor remoto" [7]. Pero en oct-2026 sigue
   **tras origin trial / flag** (Chrome ~157, nov-2026) y casi ningún agente lo consume todavía [7][8].
5. **Seguridad**: con perfil real y sesión autenticada, el prompt injection indirecto es irreducible con
   solo un LLM; Anthropic bajó el ASR de 23.6% a 11.2% con mitigaciones, no a cero [9]. La defensa real es
   **arquitectónica**: allowlist de dominios, confirmaciones, límites de token, content boundaries [9][10][11].

---

## 1. Latencia / tiempo real

### 1.1 Batch / bulk de acciones (mayor ROI, menor esfuerzo)
- `[H]` Paper "Building Browser Agents" (arXiv 2511.19477, nov-2025): `bulkActions([...])` permite despachar
  varias acciones independientes en **un solo tool-call**. En un form de 28 campos con GPT-5.1:
  **10 vs 38 tool calls (−74%), 104.5s vs 245.1s (−57%), 154K vs 260K tokens (−41%)** [2].
- `[I]` Nuestro runner ya ejecuta JS multi-paso dentro de **un** `browser-control execute` (avg_roundtrips
  medido 1.3). Formalizar `bulkActions` como primitiva reutilizable generaliza la ganancia a tareas que hoy
  son secuenciales.

### 1.2 Modelo de decisión pequeño para "próxima acción" (System One)
- `[H]` `browser-use/jev-ultrafast` (creado 2026-09-16, 772★): action space **indexado y dinámico**. En cada
  observación se genera una tabla de elementos `[1] button … [2] combobox …`; Jev (System One de TypeSafe)
  elige operación + target en **una request**; un LLM pequeño solo escribe texto cuando la operación es
  `TYPE_TEXT`. Los target questions son **especulativos**: varias preguntas en un round-trip; solo ejecuta
  la compatible con la operación elegida [1].
  - Google Flights Zürich→London: **7.073s** (1×, incluye generación de texto y esperas).
  - 6 corridas alternas: mediana **9.450s → 7.092s (−25%)**; llamadas al protocolo **1.092 → 101**.
  - Wikipedia 2.798s; hotel local 1.896s. **Sin screenshots** en el loop por defecto.
- `[H]` Jev (TypeSafe AI, lanzado sep-2026): System One, **70–500ms** por decisión vs 3–329s de frontier
  models en sus workflows; hasta **193.6× más rápido y 444.6× más barato**; primitivas `Choice` (≤255
  opciones), `Score`, `Noul`; preguntas independientes en paralelo; $0.042/1M input [12][13][14].
- `[H]` Laya (open-source, convaiinnovations/laya): decisión tipada **no-autoregresiva en un solo forward
  pass, 33ms** (7.2ms/pregunta batched en T4); ModernBERT 421M/322M; **Router** elige checkpoint por
  request; API compatible con Jev [15]. Laya se autopublica igual o mejor en accuracy en varios datasets
  (typed-decisions 0.766 vs 0.727) [15] `[S]`.
- `[I]` Para nuestro stack: Jev/Laya resuelven exactamente el problema medido ("round-trips LLM, no el
  navegador"). El patrón a copiar de jev-ultrafast es **tabla de elementos indexada + 1 decisión por
  observación**, sin strings y con confianza (encaja con la filosofía JEV/System One del usuario).

### 1.3 CDP directo, persistencia y "estado caliente"
- `[H]` Kitewright vs `@playwright/mcp` (bench 2026-07-12): la **warm-call latency es empate** (ambos hablan
  CDP al mismo Chromium ~80–116ms). La diferencia está en el arranque: cold start 354ms→75ms y
  **prewarm()** (lanzar browser durante el handshake) baja el primer navigate de ~2.6s a 31ms con contexto
  precalentado [16]. Hay un **piso de red externo** (DNS+TLS+TTFB ≈ 400–600ms) que ninguna optimización
  local vence [16].
- `[H]` OpenBrowser (raw CDP, 1 tool `execute_code`) se autopublica con 283 tokens vs 134.802
  (chrome-devtools-mcp) y 248.016 (playwright-mcp) en un workflow de 5 pasos sobre Wikipedia; duración
  media 62.7s vs 77.0s / 103.4s [17] `[S]`.
- `[H]` ComputeSDK (ixio, mediana de 100 runs, sep-2026) mide **session round-trip** (create+connect+navigate):
  Kernel 246ms, Browser Use ~436–487ms, Hyperbrowser 634ms, Browserbase 661–963ms, Steel ~1.57s,
  Notte 2.38s [18]. Browser Arena (Notte Labs) rankea Notte #1, Steel #3, Browserbase/Anchor/… con
  Hyperbrowser #7 [19] `[S]` (bench mantenido por un vendor).
- `[H]` Gotcha crítico para nosotros: `agent-browser` **cuelga al adjuntarse a un browser con pestañas
  descartadas por "Memory Saver"** (issue #1036, 2026-03-26): `Page.enable` a una pestaña sin renderer
  nunca responde. Repro sobre Brave: 14/20 tabs descartadas = timeout [20]. También #1193 (attach a Chrome
  externo cuelga, abr-2026) [21]. `[I]` Aplica a cualquier approach CDP sobre el **Brave real** (no solo
  agent-browser): hay que excluir pestañas descartadas/congeladas.

### 1.4 WebSocket vs polling, streaming de estado
- `[H]` `browser-control` (nuestro backend) ya va por **relay local + sessions**; el bench local mide 1.3
  round-trips y 3401ms t_first. `[I]` Para "casi tiempo-real" el patrón que escala es **JS persistente por
  sesión + esperas por condición** (ya usado) más un **bus de eventos** (MutationObserver → estado) en vez
  de re-observar el DOM entero por turno.
- `[H]` OWL (OpenAI Atlas, oct-2025): separa el proceso Chromium de la app; el agente compposita popups
  fuera del tab en una sola imagen y **rutea eventos del agente directo al renderer** preservando el sandbox
  [22]. `[I]` Confirma que la latencia se gana moviendo la orquestación fuera del loop perceptual.

### 1.5 Speculative execution (técnica emergente, aún research)
- `[H]` "Speculative Actions" (vía Zylos Research, 2026-04-03): un modelo rápido predice la próxima acción;
  verificable/rollback; precisión de next-action hasta **55%**, con reducción de latencia end-to-end sin
  degradar calidad. PASTE/speculative tool calls: **−48% task time** [23].
- `[H]` KV-cache / serving: CacheScout reduce TTFT 18–45% y latencia por turno 29–38% (vLLM) [24]; PBKV
  hit-rate 69.1% (2.55× LRU) [25]. `[I]` Relevante solo si corréis inferencia propia; con API hosted el
  análogo es **prompt caching** (§ visibilidad).

---

## 2. Cómo los agentes "ven" la página

| Estrategia | Latencia | Tokens | Fiabilidad | Fuente |
|---|---|---|---|---|
| Screenshot + vision | 4–10s/ciclo | 1k–2k img tok (≈2× texto) | falla en grids densos (celdas 24px), canvas | [3][4][5] |
| a11y tree (completo) | +50–200ms extracción; pero miles tok/paso | 2k–10k | alta en sitios WCAG; oculta canvas/layering | [3][4][5] |
| Set-of-Marks | labeling despreciable (≈0) | ~imagen | útil si pocos elementos; inutilizable si cientos | [3] |
| Outline JS selectivo / diff (nuestro) | 1 round-trip | **65–128 tok** | genérico vía JS | bench local [6] |
| Grid mapping (coordenadas) | — | — | descartado en producción | [2] |

- `[H]` OSWorld-Human (MLSys 2026): incluir el a11y tree **incrementa drásticamente** la latencia por tarea
  (generar el árbol + mile(s) de tokens extra en cada prompt); SoM no añade overhead significativo de
  labeling; pero en algunas apps el árbol reduce pasos y compensa [3].
- `[H]` Prophet (mayo 2026): extracción a11y **50–200ms**, string 2.000–10.000 tok; ciclo screenshot
  **4–10s**. Conclusión publicada: **2–4× más rápido por paso** con a11y; 15 pasos ≈ 30s vs 90s [4] `[S]`.
- `[H]` "Read More, Think More" (arXiv 2604.01535, abr-2026): **representaciones compactas (a11y) son
  mejores para modelos de menor capacidad; HTML detallado gana para modelos más capaces**; historia de
  observaciones ayuda; **la representación diff es una alternativa token-efficient** [26].
- `[H]` Paper de arquitectura: híbrido **a11y primario + visión selectiva** (visión solo para canvas/no
  accesible), con **element refs versionados** `1:10` (snapshot:ref) que **fallan seguro** si el estado
  cambió, y delegación a un modelo de visión con bounding boxes para contenido visual [2].
- `[H]` Self-healing / caching semántico: Stagehand v3 (2025-10-29) "44% faster", corre como **extension
  junto al browser, reduciendo round-trip latency**, con auto-caching (recuerda acciones previas y corre sin
  inferencia LLM si la página no cambió) + self-healing [27][28][29] `[S]`.

`[I]` Veredicto para `browser-pilot`: mantener el **outline JS por selectores + refs indexados** (barato) y
añadir **diff/versionado**; usar a11y completo solo como fallback de exploración; visión solo para canvas.

---

## 3. Estado de backends / frameworks

| Proyecto | Estrellas (fecha) | Motor | Perfil real | Notas |
|---|---|---|---|---|
| browser-use | ~96K (may-2026) | CDP vía `cdp-use`, fork Chromium propio | sí (`user_data_dir`) | 89.1% WebVoyager; commits sep–oct-2026 (CDP primitives #5889) [30][31] |
| Playwright MCP | ~27.4K (feb-2026) | Playwright | opt-in `--extension`/CDP | Microsoft; recomienda **CLI+Skills** [32] |
| chrome-devtools-mcp | **51.8K** (sep-2026) | Puppeteer/CDP | `--browserUrl` | Google; **stable v1.1.1**, tools WebMCP [33][34] |
| BrowserMCP/mcp | 7.1K | extension + debugger API | sí (Chrome real) | sin releases; MV3 worker muere a 30s [35] |
| Stagehand | 22.8K (may-2026) | propio (no Playwright en v3) | local/cloud | self-healing + caching [27][30] |
| browser-control | (nuestro) | extension MV3 + relay | **sí, medido** | 6.2/10 en bench local [6] |

- `[H]` Benchmarks de browser-use (mar-2026): Online-Mind2Web 98% cloud v4; BU Bench V1 78%; BrowserBench
  stealth 84.8%; pero **es auto-publicado** [36] `[S]`.
- `[H]` Online-Mind2Web (arXiv 2504.01382): 300 tareas / 136 sitios; el search agent resuelve ~22% (50%
  fácil / 18% medio / 3% hard) con éxito humano más alto [37].
- `[H]` Chrome DevTools MCP vs Playwright MCP (blog 2026-03-12): DevTools ~330K vs Playwright ~1.5M tokens
  por run (−78%), 12 vs 48–52 turnos, ~2m44s vs ~6m19s (−57%) [38] `[S]` de tercero.
- `[H]` Notte/Steel/Browserbase/Hyperbrowser/Anchor: todos managed cloud Chromium; Steel OSS self-hostable,
  agent-framework-neutral; Hyperbrowser apuesta a concurrencia/stealth; Anchor a headful+identidad [19][39].
- `[H]` Skyvern: vision-LLM planner-actor-validator para reemplazo RPA; **no** es browser runtime (no está
  en Browser Arena) [39][40].
- `[I]` Para perfil real con sesión, ninguno de cloud sirve (perfil aislado); nuestro `browser-control`
  sigue siendo la elección correcta. Lo que aportan los demás es **batching, refs y caching**, no hosting.

---

## 4. Productos / vendors

- `[H]` Operator (OpenAI, ene-2025) deprecado ago-2025; ChatGPT agent retirado ago-2026; **Atlas apagado el
  2026-08-09**, browser plegado a la app de escritorio ChatGPT + extensión de Chrome + cloud browser [41][42].
- `[H]` Google **Project Mariner apagado el 2026-05-04**; auto-browse embebido en Chrome compartiendo sesión
  real (sin disparar anti-bot) [43].
- `[H]` Claude for Chrome (beta, ago-2025; extensión a pagar dic-2025): navega, hace click, rellena forms;
  red-teaming: **23.6% ASR → 11.2%** con mitigaciones en modo autónomo. Arquitectura: la sesión/loop puede
  correr en cloud con sandbox aislado, alcanzando el browser local solo vía la app Desktop [9][44][45].
- `[H]` Anthropic "Managed Agents" (abr-2026): **desacopla "brain" (harness) de "hands" (sandbox/tools) y de
  "session" (log de eventos)**; el harness no ve credenciales [46]. `[I]` Patrón copiable para nuestro relay.
- `[H]` OWL/Atlas: Chromium fuera del proceso principal; eventos del agente al renderer [22].
- `[I]` Tendencia clara 2026: el browser-agente como **feature dentro del asistente** (ChatGPT/Claude/Gemini),
  no como navegador standalone; y la diferenciación real es **sesión real + seguridad**, no el modelo.

---

## 5. Modelos / políticas

- `[H]` System One vs System Two: Jev (RLCD, calibrado) para routing; LLM para razonamiento/texto. Recomiendan
  **routing por umbral de confianza**: baja confianza → escalar a LLM o humano [12][13][14].
- `[H]` Laya: no-autoregresivo, 33ms, entrenado contra Brier score; router por checkpoint [15].
- `[H]` jev-ultrafast: mejor caso de aplicación de System One a computer-use ("browser/computer use might be
  the perfect application for Jev" — @davecyen) [1][47].
- `[H]` RL sobre trayectorias web: WebRL (ICLR 2025) sube Llama-3.1-8B de 4.8% a **42.4%** en WebArena-Lite
  (supera GPT-4o 13.9% y GPT-4-Turbo 17.6%); DynaWeb (arXiv 2601.22149, ene-2026) usa model-based RL con
  world model; OpenWebRL (may-2026) RL online multi-turn sobre sitios vivos [48][49][50].
- `[H]` Modelos locales para actuar: **FunctionGemma-270M** (Gemma 3, tool-calling, 786MB RAM mínima) [51];
  Gemma 3 270M corre **en el navegador** (WebGPU ~200MB / WASM CPU), y por su tamaño es **base barata de
  fine-tune para clasificación/extracción/formato** [52]. `[I]` Candidato a "System One local" si no se
  quiere API: fine-tunear para "elige operación+target" sobre el element table.

---

## 6. Seguridad / privacidad con perfil real

- `[H]` Prompt injection indirecto: ataques demostrados contra Comet/Atlas (texto blanco sobre blanco,
  comentarios HTML, campos ocultos; incluso URL/título de pestaña). Anthropic: 23.6%→11.2% ASR; **no hay
  garantía** dentro del LLM [2][9][10].
- `[H]` Chrome/WebMCP recomienda **guardrails deterministas** (límite de tokens, `untrustedContentHint`,
  restringir interacción cross-origin, **confirmar acciones**) + probabilistas (spotlighting, classifiers
  tipo Model Armor) [10].
- `[H]` OWASP AI Agent Security: least privilege por tool con allowlist, validación de memoria,
  human-in-the-loop para acciones irreversibles [11].
- `[H]` `agent-browser` implementa exactamente lo que nos falta: `--allowed-domains` (bloquea navegación,
  subrecursos, WS, EventSource, sendBeacon; desactiva WebRTC), `--max-output` (anti context-flood),
  `--content-boundaries` con **nonce por proceso** para distinguir output de tool vs contenido de página,
  vault de credenciales, **confirmaciones que auto-rechazan a los 60s** [53].
- `[I]` Nuestras reglas actuales (no Meta/WhatsApp/Clerk, no acciones sensibles sin HITL) son correctas pero
  **voluntarias**; falta enforcement determinista en `browser-control` (allowlist + confirmación + boundaries).

---

## 7. Benchmarks y métricas

- `[H]` Datasets vivos: **WebVoyager** (586 tareas live), **Online-Mind2Web** (300/136 sitios),
  **WebArena** (812, self-hosted, reproducible), **WorkArena**, **MM-Mind2Web** (2.000), OSWorld (369).
  Steel agrega 14 leaderboards (~359 resultados) [19][37][54].
- `[H]` Métricas que importan: success rate, nº de steps, latencia p50/p95, tokens, coste. OSWorld-Human
  propone medir **consistencia de steps** (WES) además de éxito [3][24].
- `[I]` Nuestro `runs.jsonl` ya mide ok/ms; falta **tokens LLM reales** (hoy los adapters son scripted) —
  el bench local marca este como gap #1 para poder comparar contra la industria [6].

---

## 8. Señales X/Twitter (con fecha)

- `[H]` @gregpr07 (Gregor Zunic, browser-use), **2026-07-22**: "Grok Build, with the Browser Use CLI,
  outperforms Codex and Claude Code at browser tasks" [55].
- `[H]` @gregpr07, **2026-09-17**: "Breaking: Browser Use + Jev = Ultrafast ⚡ Findings flights took 7s and
  cost only $0.0039 🤯 > new action space every step > DOM state space > small LLM fallback to type" [47].
- `[H]` @davecyen, **2026-09-17**: "Got access to Jev and it's amazingly *fast*… Browser/computer use might
  be the perfect application for Jev" [56].
- `[H]` Capacidad de lectura de X: la tool `latestPostsX` en `lib/tasks.mjs` ya existe; en esta sesión no
  pude invocarla (sin tool `task`/browser-pilot), así que las señales vienen del índice de búsqueda web,
  no de una lectura autenticada del timeline.

---

## 9. GitHub — releases / actividad reciente

- `[H]` **chrome-devtools-mcp**: **51.8K★**, 75 issues abiertas, `stable v1.1.1` (sep-2026); PRs recientes:
  "support shared MCP server sessions" (#2733), "evaluate scripts from local files" (#2606) [33][34][57].
- `[H]` **browser-use**: commits sep–oct-2026; "Fix Actor input semantics and add CDP primitives (#5889)"
  (2026-09-26); integración Anthropic [31][58].
- `[H]` **browser-use/jev-ultrafast**: creado **2026-09-16**, 772★, 2 commits, MIT [1].
- `[H]` **stagehand**: milestones cerrados (Foundation/AI/Core Automation/Extensibility/Evaluation);
  `stagehand-net` archivado 2026-09-01 tras v3.21.0 [27][59].
- `[H]` **agent-browser** (Vercel Labs): issues #1036 (tabs descartadas) y #1193 (attach hang) — relevantes
  directamente a perfil Brave real [20][21].
- `[H]` **cdp-bridge-mcp** (Unagi-cq): 298★, MCP + extension que conecta a sesión real; eval v3 (2026-08-09)
  con Playwright MCP, 100% pass en 3 escenarios [60].

---

## Tabla comparativa de backends (latencia / fiabilidad / requisitos)

| Backend | Perfil real | Latencia (medida) | Fiabilidad | Requisitos | Fuente |
|---|---|---|---|---|---|
| **browser-control** | **sí (medido)** | t_first 3.401ms, 1.3 rt [6] | 0.83 (YouTube 0/3) [6] | extension MV3 + relay :19989 | bench local |
| stagehand | no (temp) | t_first 2.350ms, 0 rt [6] | 0.83 [6] | LLM key | bench local |
| chrome-devtools-mcp | condicional | t_first 3.076ms, 3.5 rt; 4.542 tok [6] | 0.83 [6] | Chrome + `--browserUrl` | bench local |
| brave-mcp | attach Brave real | t_first 3.620ms, 3.5 rt [6] | 0.83 [6] | fork | bench local |
| agent-browser | copia read-only | t_first 4.158ms, 6.2 rt [6]; attach cuelga con tabs descartadas [20] | 0.83 [6] | Rust CLI | bench local |
| playwright-mcp | solo via extension/CDP | warm CDP ~80–116ms; cold nav 2.6s [16] | alto en CI | Node + browsers | [16][32] |
| OpenBrowser | CDP perfil real | 62.7s vs 77–103s (5 pasos) [17] | — | `execute_code` | [17] `[S]` |
| Kernel / Browser Use / Hyperbrowser / Browserbase / Steel / Notte | no (cloud) | round-trip 246 / 436 / 634 / 661 / 1570 / 2380 ms [18] | 100/100 [18] | managed cloud | [18] `[S]` |

---

## Ranked: cosas a implementar realmente para `browser-pilot`

Impacto: alto/medio/bajo. Esfuerzo: S/M/L. Integra con `pilot.mjs` / `tasks.mjs` / `selectors.json` /
`browser-control`.

### 1. `bulkActions` como primitiva del runner (impacto **alto**, esfuerzo **S**)
- **Qué**: exponer en `lib/tasks.mjs` un helper que emita una lista JSON de pasos (type/select/click) y los
  ejecute en **un** `browser-control execute`, con snapshot versionado.
- **Por qué**: −74% tool calls, −57% tiempo, −41% tokens en forms [2]. Hoy ya aprovechamos 1 execute por
  tarea, pero no está formalizado ni versionado.
- **Integración**: `tasks.mjs` (generador) + `pilot.mjs` (1 execute) + `selectors.json` (mapa de campos).
- **Fuente**: arXiv 2511.19477 §5.3 [2].

### 2. Decisión "próxima acción" con System One (Jev API o Laya local) (impacto **alto**, esfuerzo **L**)
- **Qué**: portar el patrón jev-ultrafast: observación → **element table indexada** (`[n] rol · nombre · valor`)
  → una llamada a Jev/Laya que devuelve `operation` + `target` con confianza → LLM pequeño solo para
  `TYPE_TEXT`. Umbral de confianza → escalar a LLM/humano.
- **Por qué**: exactamente el cuello medido (orquestación). Evidencia: −25% task, ×10.8 menos llamadas de
  protocolo, sin screenshots [1]; Jev 70–500ms vs segundos [12]; Laya local 33ms sin API key [15].
- **Integración**: nuevo `lib/systemone.mjs`; `pilot.mjs` cambia de "script fijo" a loop dirigido; la
  element table reusa `selectors.json`; `runs.jsonl` registra `decision_ms` y `confidence`.
- **Fuente**: [1][12][15].

### 3. Snapshot por **diff + refs versionados** (impacto **alto**, esfuerzo **M**)
- **Qué**: en cada observación devolver solo el **delta** del outline/element table desde el turno previo, y
  asignar refs `version:ref` que **fallan seguro** si el DOM cambió; re-chequear oclusión antes de click.
- **Por qué**: diff es token-efficient [26]; evita clicks en elementos stale (reliability) [2]. Nuestro
  outline ya es barato (65–128 tok) [6]; el diff lo hace aún más y habilita loops largos.
- **Integración**: `pilot.mjs` (injected `snapshot()` en page) + `selectors.json`; `runs.jsonl` anota diff_bytes.
- **Fuente**: [2][26].

### 4. Auto-caching + self-healing de selectores sobre `runs.jsonl` (impacto **alto**, esfuerzo **M**)
- **Qué**: cachear selectores resueltos por **firma de página** (URL+hash de estructura), correr sin
  re-resolver cuando la firma coincide, y al fallar hacer **fallback semántico** (rol+nombre accesible) antes
  de abortar; actualizar `selectors.json`/`playbooks` automáticamente.
- **Por qué**: Stagehand v3 corre sin inferencia cuando la página no cambió, 44% faster, y se auto-repara [27][28][29].
- **Integración**: `runlog.mjs` (ya loguea) → nuevo `selectors-cache.json` + fallback en `pilot.mjs`.
- **Fuente**: [27][28][29].

### 5. Soporte WebMCP con feature-gate (impacto **medio-alto**, esfuerzo **S**)
- **Qué**: antes de scrapear, chequear `document.modelContext?.getTools()` (con guard de carga y polyfill) y,
  si hay tools, invocarlas en vez de actuar por DOM.
- **Por qué**: cuando exista, es "casi instantáneo, sin round-trip a servidor remoto" y mucho más fiable que
  actuation [7]. Hoy sigue tras flag (Chrome ~157, nov-2026) [7][8], coste de estar temprano = bajo.
- **Integración**: helper en `lib/tasks.mjs`; `selectors.json` gana sección `webmcp`; fallback al DOM actual.
- **Fuente**: [7][8].

### 6. Enforcement de seguridad determinista en `browser-control` (impacto **alto**, esfuerzo **S**)
- **Qué**: allowlist de dominios (bloquear navegación/subrecursos/WS/WebRTC fuera de lista), `--max-output`
  anti context-flood, **content boundaries con nonce**, confirmación con **timeout fail-closed**.
- **Por qué**: con perfil real y sesión autenticada el injection es real (23.6%→11.2% con mitigaciones) [9];
  el patrón ya está probado en agent-browser [53].
- **Integración**: skill `browser-pilot` + wrapper sobre `browser-control`; `runs.jsonl` loguea bloqueos.
- **Fuente**: [9][10][11][53].

### 7. Excluir pestañas descartadas/congeladas del attach CDP (impacto **medio**, esfuerzo **S**)
- **Qué**: al abrir/attach sesión, saltar tabs `discarded/frozen` (Memory Saver) y no mandar `Page.enable` a
  tabs sin renderer; pre-warm de la sesión antes de la primera acción.
- **Por qué**: `Page.enable` a tab descartada **cuelga para siempre** (14/20 en Brave) [20]; prewarm baja el
  primer navigate a ~31ms [16].
- **Integración**: wrapper en `pilot.mjs`/`browser-control` + timeout por fase.
- **Fuente**: [20][21][16].

### 8. Router por confianza con escalado a LLM (impacto **medio**, esfuerzo **M**)
- **Qué**: umbral en código: si `confidence < τ`, escalar la decisión a un LLM (o cola humana); nunca forzar
  una rama frágil.
- **Por qué**: patrón recomendado por TypeSafe/Jev [12][14]; reduce errores sin pagar LLM siempre.
- **Integración**: `lib/systemone.mjs` + `pilot.mjs`; `runs.jsonl` anota escalados.
- **Fuente**: [12][14].

### 9. API/RSS-first sobre scraping (impacto **medio**, esfuerzo **M**)
- **Qué**: para cada sitio nuevo, buscar endpoint estructurado (RSS/JSON) antes de DOM; documentar en el
  playbook. Ya probado con YouTube RSS (`playLatestChannelTopic`, ~4.8s).
- **Por qué**: evita anti-bot y reduce pasos a ~1 fetch; el anti-bot sobre perfil persistente es el fallo
  reproducible de nuestro bench (YouTube 0/3) [6].
- **Integración**: `tasks.mjs` + `playbooks/<site>.md`.
- **Fuente**: bench local [6] + [61] (Cloudflare documenta WebMCP y scrapers).

### 10. Batch de observaciones y streaming de estado (impacto **medio**, esfuerzo **L**)
- **Qué**: MutationObserver → event bus por sesión; el agente reacciona a cambios sin re-observar todo.
- **Por qué**: elimina re-observación por turno; base para "casi tiempo-real" [2][22].
- **Integración**: `browser-control` sessions + `pilot.mjs`.
- **Fuente**: [2][22].

---

## Confianza

- **Alta**: batching (arXiv + reproducción conceptual en nuestro runner), a11y vs screenshots trade-off
  (múltiples fuentes independientes), caída de Operator/Atlas/Mariner (docs oficiales/Wikipedia),
  ASR 23.6%→11.2% (Anthropic), agent-browser tabs descartadas (issue reproducible), WebMCP tras flag/origin
  trial (docs Chrome + tracker).
- **Media**: números de jev-ultrafast (3 repeticiones, un task, un perfil — auto-publicado), cifras de
  latency de cloud (ComputeSDK/Browser Arena son de vendors), Jev 193.6×/70–500ms (blog del vendor con
  metodología declarada), Laya vs Jev (Laya no mide Jev, usa cifras publicadas).
- **Baja**: leaderboard "WebVoyager #1 browser-control (Om Labs) 99.19%" — **colisión de nombre** con nuestro
  `browser-control`; no verificado y probablemente otro producto. Rankings de framework "quién gana en
  latencia" fuera de benchmarks controlados.

---

## Huecos / cómo verificar

1. **No pude delegar a `browser-pilot`**: esta sesión no expone la tool `task` (ni subagente browser-pilot).
   Verificar: correr en una sesión main con `task(subagent_type:"browser-pilot")` para leer X autenticado y
   GitHub trending; pedir que deje el crudo en un archivo. Las señales X de §8 vienen del índice de búsqueda.
2. **X autenticado**: `latestPostsX` no se ejecutó; los tweets citados son de resultados de búsqueda con URL,
   no de lectura de timeline. Verificar con browser-pilot.
3. **Números de jev-ultrafast**: replicar localmente con nuestro Brave (mismo task, 3 repeticiones) para
   aislar cuánto aplica a `browser-control`.
4. **WebMCP end-to-end**: probar `document.modelContext.getTools()` en el Brave real con el flag
   `chrome://flags/#enable-webmcp-testing`; medir si algún sitio objetivo ya lo expone.
5. **Tokens LLM reales**: el bench local no mide razonamiento LLM; instrumentar `pilot.mjs` para loguear
   input+output tokens por decisión (gap #1 declarado en `RANKING.md`).
6. **Funcionamiento de Jev/Laya**: probar Laya self-hosted (33ms) contra la API Jev; medir calibration y
   accuracy en "elige target" sobre una element table real, antes de adoptar.

---

## Fuentes

1. browser-use/jev-ultrafast — https://github.com/browser-use/jev-ultrafast (creado 2026-09-16; README)
2. Vardanyan, "Building Browser Agents: Architecture, Security, and Practical Solutions" — https://arxiv.org/html/2511.19477v1 (2025-11-22)
3. OSWorld-Human: Benchmarking the Efficiency of Computer-Use Agents — https://arxiv.org/html/2506.16042v2 (MLSys 2026; v1 jun-2025)
4. Prophet, "Why Screenshot AI Agents Are 2–4× Slower" — https://prophetchrome.com/blog/accessibility-tree-vs-screenshots-browser-ai (2026-04-22/05)
5. DEV, "The accessibility tree is the new API" — https://dev.to/ssmancha/the-accessibility-tree-is-the-new-api-1hm4 (2026-04-15)
6. Bench local — ~/.config/opencode/skills/browser-bench/SCORES.md, RANKING.md (r8, 2026-10)
7. Chrome for Developers, "WebMCP" — https://developer.chrome.com/docs/ai/webmcp (pub. 2026-05-18, act. 2026-08-07)
8. webmcp.com ecosystem tracker — https://webmcp.com/ecosystem-status (verificado 2026-08-07)
9. Anthropic, "Piloting Claude in Chrome" — https://www.anthropic.com/news/claude-for-chrome (2025-08-25)
10. Chrome for Developers, "Agent security considerations for WebMCP" — https://developer.chrome.com/docs/agents/security (2026-06-09)
11. OWASP, "AI Agent Security Cheat Sheet" — https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html
12. TypeSafe AI, "Introducing System One Models & Jev" — https://typesafe.ai/blog/introducing-system-one-models-and-jev (sep-2026)
13. Jev System One (community) — https://jevtypesafeai.com/jev/system-one
14. Vercel Changelog, "TypeSafe AI's Jev now available on AI Gateway" — https://vercel.com/changelog/typesafe-ai-jev-now-available-on-ai-gateway (2026-09-16)
15. convaiinnovations/laya — https://huggingface.co/convaiinnovations/laya y https://github.com/artificial-intelligence-works/laya-jev
16. Kitewright BENCHMARKS.md — https://github.com/kitewright/kitewright/blob/main/BENCHMARKS.md (2026-07-12)
17. OpenBrowser, Benchmark Comparison — https://docs.openbrowser.me/comparison (MCP bench 2026-02-21)
18. ixio / ComputeSDK, browser latency — https://ixio.com/browser (medido 2026-08-28; agregado 2026-09-11)
19. Notte answers (Hyperbrowser vs Steel, Anchor vs Steel, Browser Use vs Hyperbrowser) — https://ai.notte.cc/answers/hyperbrowser-vs-steel (2026-05-22)
20. agent-browser issue #1036 — https://github.com/vercel-labs/agent-browser/issues/1036 (2026-03-26)
21. agent-browser issue #1193 — https://github.com/vercel-labs/agent-browser/issues/1193 (2026-04-08)
22. OpenAI, "How we built OWL… Atlas" — https://openai.com/index/building-chatgpt-atlas (2025-10-30)
23. Zylos Research, "Inference Acceleration for AI Agent Loops" — https://zylos.ai/research/2026-04-03-inference-acceleration-ai-agent-loops (2026-04-03)
24. "Learning Agent Execution for KV-Cache Management (CacheScout)" — https://arxiv.org/abs/2608.14624 (2026-07-16)
25. "Efficient Serving for Dynamic Agent Workflows (PBKV)" — https://arxiv.org/pdf/2605.06472
26. "Read More, Think More: Revisiting Observation Reduction for Web Agents" — https://arxiv.org/pdf/2604.01535 (2026-04-02)
27. Browserbase, "Stagehand v3: Faster AI Automation, No Playwright" — https://www.browserbase.com/blog/stagehand-v3 (2025-10-29)
28. Browserbase Stagehand — https://www.browserbase.com/stagehand
29. Stagehand docs — https://docs.browserbase.com/welcome/quickstarts/stagehand
30. Ascero AI News, "Browser-Use Hits 96K Stars" — https://asceroai.com/news/browser-use-stagehand-agent-frontier-2026 (2026-05-28)
31. browser-use commits — https://github.com/browser-use/browser-use/commits/main/ (sep–oct-2026)
32. BAP browser-tools-guide — https://github.com/browseragentprotocol/bap/blob/main/docs/browser-tools-guide.md
33. ChromeDevTools/chrome-devtools-mcp — https://github.com/chromeDevTools/chrome-devtools-mcp (51.8K★, sep-2026)
34. Chrome DevTools blog, "What's new in DevTools (Chrome 149)" — https://developer.chrome.com/blog/new-in-devtools-149 (2026-06-02)
35. BrowserMCP/mcp — https://github.com/browsermcp/mcp (7.1K★)
36. Browser Use benchmarks — https://browser-use.com/benchmarks.md (testing mar-2026)
37. "An Illusion of Progress? Online-Mind2Web" — https://arxiv.org/html/2504.01382v4
38. Serkan Özal, "Browser DevTools MCP — 78% Fewer Tokens vs. Playwright MCP" — Medium (2026-03-12)
39. Notte, Skyvern vs Steel — https://ai.notte.cc/answers/skyvern-vs-steel (2026-05-22)
40. Notte, Browser Use vs Skyvern — https://ai.notte.cc/answers/browser-use-vs-skyvern (2026-05-22)
41. Wikipedia, "OpenAI Operator" — https://en.wikipedia.org/wiki/OpenAI_Operator (act. 2026-09-02)
42. OpenAI Help, "Evolving Atlas into ChatGPT…" — https://help.openai.com/articles/20001371 (Atlas stop 2026-08-09)
43. yage.ai, "Google Killed Project Mariner" — https://yage.ai/share/google-project-mariner-shutdown-en-20260511.html (2026-05-11)
44. Claude for Chrome — https://claude.com/claude-for-chrome
45. Anthropic, "How we contain Claude across products" — https://www.anthropic.com/engineering/how-we-contain-claude (2026-05-25)
46. Anthropic, "Scaling Managed Agents" — https://www.anthropic.com/engineering/managed-agents (2026-04-08)
47. @gregpr07, X — https://x.com/gregpr07/status/2100411066966749359 (2026-09-17)
48. WebRL — https://arxiv.org/abs/2411.02337 (ICLR 2025)
49. DynaWeb — https://arxiv.org/html/2601.22149v2 (2026-01-30)
50. OpenWebRL — https://github.com/OpenWebRL/OpenWebRL (2026-05-27)
51. google/functiongemma-270m — https://lmstudio.ai/models/google/functiongemma-270m
52. Gemma 3 270M en browser — https://webai.show/models/gemma-3-270m
53. agent-browser security docs — https://github.com/vercel-labs/agent-browser/blob/main/docs/src/app/security/page.mdx
54. Steel leaderboard — https://leaderboard.steel.dev/results (jun-2026)
55. @gregpr07, X — https://x.com/gregpr07/status/2080028066160775670 (2026-07-22)
56. @davecyen, X — https://x.com/davecyen/status/2100423988707303676 (2026-09-17)
57. chrome-devtools-mcp PRs — https://github.com/ChromeDevTools/chrome-devtools-mcp/pulls (sep-2026)
58. browser-use/jev-ultrafast performance.md — https://github.com/browser-use/jev-ultrafast/blob/main/docs/performance.md
59. stagehand-net releases — https://github.com/browserbase/stagehand-net/releases (archivado 2026-09-01)
60. cdp-bridge-mcp — https://github.com/Unagi-cq/cdp-bridge-mcp (298★, 2026-05-07)
61. Cloudflare Browser Run, WebMCP — https://developers.cloudflare.com/browser-run/features/webmcp
