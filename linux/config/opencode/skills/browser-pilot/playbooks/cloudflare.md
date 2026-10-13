# Playbook: Cloudflare Dashboard

## Estado
- verified: 2026-10-06
- perfil: BRAVE REAL del usuario (sesion via browser-control, `--read-only`)
- login: sesion persistente; no re-loguear.

## Rutas
- Account home: `https://dash.cloudflare.com/<accountId>/home`
- Zone DNS records: `https://dash.cloudflare.com/<accountId>/<zone>/dns/records`

## API interna (misma origin, cookie-auth)
La SPA usa `https://dash.cloudflare.com/api/v4/...` (NO `api.cloudflare.com` para el dashboard).
Se puede replicar desde `page.evaluate` con `fetch(..., {credentials:'include'})`:
- Listar zona: `/api/v4/zones?name=<zone>&account.id=<acct>&type=full,partial,secondary`
- DNS todos: `/api/v4/zones/<zoneId>/dns_records?per_page=200&order=type&direction=asc`
- Filtrar: `...?type=MX`, `...?type=TXT`, `...?type=TXT&name=_dmarc.<zone>`
El JSON trae `result_info.total_count` -> confirma si hay paginacion.

## Recetas
- Para volcar registros relevantes sin truncar el tool output: parsear el JSON DENTRO del
  response handler y devolver solo `{type,name,content,priority,proxied,ttl}`.
- Evitar devolver bodies crudos grandes: browser-control trunca `value` y marca `valueUnavailable`.

## Escritura (POST) — gotcha
`fetch` POST a `/api/v4/zones/<zoneId>/dns_records` desde `page.evaluate` devuelve **403
text/html** (el gateway del dashboard exige un token que la SPA adjunta). No se puede crear
editar por `fetch` cookie-auth. Para escribir: **usar la UI**.

## Receta UI: crear un registro TXT
`https://dash.cloudflare.com/5177763f7548ba70031bb586ff558763/autotechivi.com/dns/records`
1. boton `Add record` (rol button, texto exacto) -> se abre `[role="dialog"]` heading "Add record".
2. Type: `dialog.getByRole('combobox').first().click()`, luego
   `page.getByRole('option', { name: 'TXT', exact: true }).click()`.
3. Name: `page.getByPlaceholder('Use @ for root').fill('_dmarc')` (placeholder es estable).
4. Content: `dialog.locator('textarea').fill('v=DMARC1; p=none;')` (el content de TXT es un
   TEXTAREA, no input; los `[role=combobox]` y su `-hidden-input` son base-ui).
5. Save: `dialog.getByRole('button', { name: 'Save', exact: true }).click()`. Antes, `Save`
   queda `disabled` hasta que Name y Content tienen valor.
6. Verificar: `waitForTimeout(2000)` + `[role="dialog"]` count = 0 + releer `/dns_records?type=TXT`.
   Nota: la tabla re-renderiza async; si un locator `table tr` da 0, reintentar o usar el API GET.

## Verificacion DNS externa
`node -e "require('dns').promises.resolveTxt('_dmarc.autotechivi.com')"` (o setServers 1.1.1.1).
Cloudflare API devuelve TXT con comillas (`"v=DMARC1; p=none;"`); el valor DNS real va sin comillas.

## Gotchas
- El `zone id` es distinto del account id; sacarlo del endpoint `/zones`.
- Proxy naranja: `proxied:true`. Registros Clerk (CNAMEs) van `proxied:false`.
- `Add record` panel deja un portal/dialog; la primera captura de `ref` puede expirar. Preferir
  locators por rol/placeholder en vez de `ref()` para este flujo.
