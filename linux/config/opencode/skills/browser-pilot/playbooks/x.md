# Playbook: X (twitter)

## Estado
- verified: 2026-10-06
- perfil: BRAVE REAL del usuario (sesion viva via browser-control)

## Verdades aprendidas
- Home logueado: `https://x.com/home` (SPA).
- Selectores:
  - post = `article[data-testid="tweet"]`
  - texto = `[data-testid="tweetText"]`
  - autor = `[data-testid="User-Name"]`
- Esperar por condicion: `waitForFunction(() => document.querySelectorAll('article[data-testid="tweet"]').length>=1)`.
- El bloqueador de Brave provoca `ERR_BLOCKED_BY_CLIENT` en recursos: inofensivo.

## Recetas
- Traer ultimos posts: `latestPostsX` (`--limit 6`).

## Gotchas
- SPA: no usar sleeps largos; esperar por el primer `tweet`.
- No automatizar acciones (post/like/follow) sin human-in-the-loop.
