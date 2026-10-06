# browser-pilot

Memoria + velocidad para computer-use sobre el **Brave real** del usuario (via
`browser-control`, relay :19989 + extension MV3). Independiente del harness de benchmark.

## Por que existe
Sin memoria, cada tarea reinventa selectores y espera con sleeps fijos (lento: la tarea de
illojuan tardo 2m20s). Con playbooks + waits por condicion + sesion viva, el mismo objetivo
baja a ~10-15s y 1 tiro.

## Capas
1. Memoria de trabajo: sesion viva de browser-control (mantiene pestana y DOM entre llamadas).
2. Memoria de largo plazo: `playbooks/` (por sitio) + `runs.jsonl` (log append-only de cada tarea real).
3. Auto-mejora: correr, medir, y actualizar el playbook; un verifier detecta selectores podridos.

## Uso
```
node ~/.config/opencode/skills/browser-pilot/lib/pilot.mjs <tarea> --session <id> [args] [--json]
node .../lib/pilot.mjs --stats
```
Tareas:
- `playLatestYouTube --channel IlloJuan_`
- `playLatestChannelTopic --channel IlloJuan_ --query "GTA San Andreas 2026"`
- `searchPlayYouTube --query "el muñe"`
- `latestPostsX [--limit 6]`
- `wikiSummary --page Inteligencia_artificial`

`--session` o env `PILOT_SESSION`. La sesion debe existir (browser-control crea su pestana en el
Brave real). El runner inlinea selectores desde `selectors.json`, escribe el script en /tmp,
ejecuta `browser-control execute --file`, mide ms, y appendea a `runs.jsonl`.

## Reglas
- Waits por condicion (waitForFunction/waitForSelector del elemento real). NUNCA sleeps fijos.
- El codigo de execute corre en Node/Playwright, NO en la pagina: usar `page.evaluate` para DOM.
- Tareas devuelven `JSON.stringify({ ok, ... })`.
- NO automatizar acciones sensibles (post/like/follow/comprar) sin human-in-the-loop.
- NO loguear/automatizar Meta/WhatsApp/Clerk. Sin exfiltrar cookies. Sin comentarios en codigo.

## Auto-mejora
Tras una tarea: si un selector fallo, actualizar `selectors.json` + `playbooks/<site>.md` y anotar
`verified`. `pilot.mjs --stats` da okRate y avgMs por tarea; usar esos numeros para mejorar.
Verificacion estructural: `verify run browser` (sin red).
