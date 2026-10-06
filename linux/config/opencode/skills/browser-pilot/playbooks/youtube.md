# Playbook: YouTube

## Estado
- verified: 2026-10-06
- perfil: BRAVE REAL del usuario (sesion viva via browser-control)

## Verdades aprendidas
- Canal illojuan real: `/@IlloJuan_` (`/@illojuan` da 404).
- La pestana `/videos` usa LAYOUT NUEVO: **no existe** `a#video-title`.
  - item = `yt-lockup-view-model`
  - titulo = `.yt-lockup-metadata-view-model__title`
  - link = `a[href*="watch?v="]` dentro del item
- La busqueda (`/results?search_query=`) todavia sirve `a#video-title` / `ytd-video-renderer #video-title`.
- Render lento/lazy: la cabecera logueada tarda ~8s. NO usar sleeps fijos.
- Esperar por condicion: `waitForFunction(el => document.querySelectorAll(sel).length>=3)`.
- RSS del canal: `https://www.youtube.com/feeds/videos.xml?channel_id=<UC...>` da los 15
  ultimos con `<published>` ISO (determinista, sin render). channel_id desde
  `meta[itemprop="identifier"]` en `/@handle`.
- `waitForSelector` de un `<meta>` exige `{ state: 'attached' }` (esta hidden, el default
  `visible` hace timeout).

## Recetas
- Ultimo video de un canal: `playLatestYouTube` (`--channel IlloJuan_`).
- Reproducir 1er resultado de busqueda: `searchPlayYouTube` (`--query "..."`).
- Video mas reciente de un tema DENTRO de un canal:
  `playLatestChannelTopic --channel IlloJuan_ --query "GTA San Andreas 2026"`.
  Backend = **RSS**, no scraping: `meta[itemprop="identifier"]` -> channel_id ->
  `feeds/videos.xml?channel_id=` (ultimos 15, con `published`). Filtrar por tokens
  (score >= ceil(tokens/2)), ordenar por `published` desc. ~5s, sin scroll ni relevancia.

## Gotchas
- El codigo de `execute` corre en Node/Playwright, NO en la pagina: usar `page.evaluate` para `document`.
- Extractor YouTube: `waitForFunction` + `waitForSelector('video')` garantizan estado real, sin sleeps.
- Bloqueador de Brave puede lanzar `ERR_BLOCKED_BY_CLIENT` en recursos: inofensivo.
- `/@canal/search?query=` a veces queda en `/@canal/search` sin query si el goto se corta:
  verificar `page.url()` y re-navegar con la URL completa.
