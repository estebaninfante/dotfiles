# Playbook: Clerk Dashboard

## Estado
- verified: 2026-10-06
- perfil: BRAVE REAL del usuario (sesion via browser-control, `--read-only`)
- login: sesion persistente en el Brave real; no re-loguear.

## Layout / rutas utiles (prod instance)
- Apps list: `https://dashboard.clerk.com/apps`
- Overview prod: `/apps/<appId>/instances/<instanceId>`
- Dominios (frontend + email): `/apps/<appId>/instances/<ins>/domains`
- Detalle dominio (registros DNS que Clerk pide): `/apps/<appId>/instances/<ins>/domains/<dmn_id>`
- Emails templates: `/apps/<appId>/instances/<ins>/customization/email`
- Editor template (From/Reply-to): `/apps/<appId>/instances/<ins>/customization/email/<template>/edit`
- Instance settings: `/apps/<appId>/instances/<ins>/instance-settings`

## API interna (dapi.clerk.com)
La SPA llama `https://dapi.clerk.com/v1/instances/<ins>/...` con auth del dashboard.
Endpoints observados (JSON):
- `/domains` -> lista dominios + checks dns (CNAMEs, `mail.status`).
- `/domains/<dmn_id>/status` -> estado detallado (dns/ssl/mail/`secondary_email`).
- `/bff/api_keys`, `/webhooks`, `/billing_settings`, `/updates`.

## Como sacar la config sin clickear
- El server render embebe el instance config en el payload de Next.js (`self.__next_f.push`):
  claves utiles `from_email_domain_name`, `auth_emails_from`.
- El editor de template expone: `input[name="from_email_name"]` (+ sufijo `@<dominio>`),
  `input[name="reply_to_email_name"]`, `input[name="subject"]`; local part vacio = default.

## Gotchas
- El checklist "Email setup / Configure domain" sigue visible aunque Email este verificado.
- `Email` en `/domains/<dmn>` muestra N/3 Verified con los CNAMEs (clkmail, clk._domainkey, clk2._domainkey).
- `Secondary email`: feature para 2do proveedor (deliverability), off por defecto.
- No volcar secret keys del endpoint `/bff/api_keys`.

## Auth a dapi desde browser-control (2026-10-06)
- `fetch` del page con `credentials:'include'` a dapi da CORS/403. NO sirve.
- Token correcto: `await page.evaluate(() => window.Clerk.session.getToken())` (JWT ~1.4k).
- Usar `page.context().request.get('https://dapi.clerk.com'+path, { headers:{ authorization:'Bearer '+token, accept:'application/json' } })`.
- Endpoints utiles (instance-scoped): `/v1/instances/<ins>`, `/webhooks`, `/webhooks/svix`, `/domains`, `/bff/api_keys`, `/organizations`, `/users`.
- `/v1/instances/<ins>` (dapi) trae `auth_emails_from`, `from_email_domain_name`, `home_origin`, `active_display_config` (redirect URLs).
- El checkout de la SPA corre en Node con dynamic import (`await import('node:fs')`); `require` NO existe.

## Backend API con sk_live (api.clerk.com)
- `GET /v1/instance` (no instance-scoped). `POST /v1/organizations {name}` crea org; si slugs estan off, `slug` da error `organization_slugs_disabled` -> crear sin slug (auto-slug con timestamp). Org sin `created_by`/members si no hay users.
- `GET /v1/organizations`, `GET /v1/organizations/<id>/memberships`.
- `GET /v1/webhooks` da 404: webhooks NO estan en Backend API, solo dashboard/Svix.

## Webhooks (Svix App Portal embebido)
- La pagina `/webhooks` monta un `<iframe src=app.svix.com>` autenticado por one-time-token.
- Crear: `frame.locator('...Add Endpoint').click()`, `frame.fill('#url', url)`, tildar eventos con `frame.locator('[id="eventTypes-<slug>"]').evaluate(el=>{if(!el.checked)el.click()})` (el `.check()` falla: input oculto), y click a `Create` via evaluate (el locator resuelve a boton no visible).
- El POST de creacion devuelve `id` + `filterTypes` pero SIN secret. El secreto se revela en el detalle `/endpoints/<ep_id>`: `button[aria-label="Click to reveal"]` y se lee `#stat-signing-secret .css-194vbgm` (`whsec_...`). El fetch directo al API del portal da 401 (requiere bearer del one-time-token, no cookie).
- Complemento dapi: `/v1/instances/<ins>/webhooks` lista `subscribed_events` y `enabled`.

## Produccion: paths / allowed origins
- NO hay campo "Allowed origins" para produccion (solo aplica a extension/Electron/Capacitor). Backend API devuelve `allowed_origins: null`.
- El equivalente es Home URL en `/paths` + redirect URLs en `active_display_config` (`after_sign_in_url`, `after_sign_up_url`, etc.).

## Seguridad
- NUNCA imprimir `sk_live_`/`whsec_` en chat/log; escribir a archivo `chmod 600` y reportar solo len/last4/sha256 corto.
