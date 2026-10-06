# Chrome Web Store — install extension in the real Brave

Backend probado: Playwright `chromium.connectOverCDP('http://127.0.0.1:9222')` (Brave real ya
corre con `--remote-debugging-port=9222`). `browser-control execute` NO sirve para esto: su
`page.goto` a `chromewebstore.google.com` falla con `Page.navigate ... Not allowed`.

## Instalar
1. Abrir la ficha con CDP HTTP: `PUT http://127.0.0.1:9222/json/new?<url-encoded-detail-url>`.
2. Localizar el boton "Add to Brave" (o "Añadir a Brave"). Esta en el DOM normal (no shadow
   cerrado); basta `getBoundingClientRect()` para sacar el centro.
3. Click con gesto real: `page.mouse.move(x,y); page.mouse.click(x,y)` (o `Input.dispatchMouseEvent`).
   Un click confiable instala sin dialogo extra en Brave. Al exito el boton pasa a "Remove from Brave".
4. Verificar con `chrome://extensions` via `chrome.developerPrivate.getExtensionsInfo(...)` en el
   contexto de esa pagina: `state === "ENABLED"`, `location === "FROM_STORE"`. Playwright filtra
   targets `chrome://`, usar WebSocket CDP crudo (Node global `WebSocket`) para evaluar ahi.

## Configurar (sin pelear con la UI)
La extension guarda todo en `chrome.storage.local` bajo la clave `settings`. Abrir
`chrome-extension://<id>/options.html` en una pestana y hacer un merge profundo + `set`. El
background escucha `storage.onChanged` y rearma la alarma.

Esquema (AI Chat Exporter 1.3.0):
- settings: `downloadFolder` (`default`|`by-platform`|`custom`), `customFolderName`,
  `defaultFormat` (`markdown`|`pdf`), `askForSaveLocation`, ...
- `scheduledExport`: `enabled`, `checkIntervalMinutes` (1..10080, default 15),
  `platforms.{chatgpt,claude,gemini,deepseek,grok}.{enabled,frequency,intervalMinutes,maxPerRun,maxConcurrentConversations}`,
  `defaultFormat` (siempre markdown), `closeTabAfterExport`, `requestDelayMs` (1000..10000),
  `maxTotalPerRun` (1..200), `maxConcurrentPlatforms` (1..3).
- `frequency`: `hourly|every6h|daily|weekly|custom`. `custom` usa `intervalMinutes` (1..10080).
  Para "rolling ~30 min": `frequency:"custom"`, `intervalMinutes:30`, `checkIntervalMinutes:30`.

Ruta options: `chrome-extension://kdafdajkiljhghecdkeogldafhjgmgpk/options.html`.

## Gotchas
- El banner "Switch to Chrome to install extensions and themes" con boton "Install Chrome"
  aparece en Brave pero NO bloquea: el boton real "Add to Brave" igual esta en la ficha.
- Checkbox de proveedores: no hay; el on/off por proveedor es `scheduledExport.platforms[x].enabled`.
- Verificar alarma: `chrome.alarms.getAll()` en la options page -> `scheduled-export-check`
  `periodInMinutes` debe igualar el intervalo.
