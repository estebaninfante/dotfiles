import { execFile } from 'node:child_process'
import { promisify } from 'node:util'

const run = promisify(execFile)
const BIN = 'browser-control'

export const name = 'browser-control'
export const kind = 'mcp+cli+skill'
export const realProfile = true
export const notes =
  '@opencode-ai/browser-control: relay local + extension MV3 adjunta a un navegador real. JS persistente por sesion => pocos roundtrips.'

export async function available() {
  try {
    await run(BIN, ['--version'], { timeout: 10000 })
    return true
  } catch {
    return false
  }
}

export async function runScenario(scenario, ctx) {
  const env = { ...process.env }
  delete env.BROWSER_CONTROL_SESSION
  const call = async (code, opts = {}) => {
    ctx.note(code)
    const r = await ctx.exec(BIN, ['execute', code], { env, timeoutMs: opts.timeoutMs ?? scenario.timeoutMs })
    ctx.note(r.stdout || '')
    return r
  }

  if (scenario.id.startsWith('explore')) return await exploreRun(scenario, ctx, call)
  if (scenario.id === 'auth_roundtrip') return await authRoundtrip(scenario, ctx, call)
  if (scenario.id === 'spa_task') return await spaRun(scenario, ctx, call)

  const builders = { public_nav: publicNavJs, youtube_light: youtubeJs }
  const builder = builders[scenario.id]
  if (!builder) return { success: false, detail: 'escenario no soportado' }

  const r = await call(builder(scenario))

  if (scenario.id === 'public_nav') {
    const title = match(r.stdout, /title:\s*'([^']*)'/)
    const hasDoc = /hasDoc:\s*true/.test(r.stdout)
    ctx.note(`title=${title} hasDoc=${hasDoc}`)
    const success = (title && title.includes(scenario.expectTitle)) || hasDoc
    if (success) ctx.useful()
    return { success, detail: `title="${title}"`, data: { title, hasDoc } }
  }

  const raw = match(r.stdout, /titles:\s*'([^']*)'/)
  const titles = raw ? raw.split(' ||| ').filter(Boolean) : []
  const url = match(r.stdout, /url:\s*'([^']*)'/)
  ctx.note(`${titles.length} titulos ${url}`)
  const success = titles.length >= scenario.minTitles
  if (success) ctx.useful()
  return { success, detail: `${titles.length} titulos url=${url}`, data: { titles } }
}

function publicNavJs(scenario) {
  return [
    `await page.goto(${JSON.stringify(scenario.url)})`,
    `const title = await page.title()`,
    `const text = await page.$eval('body', el => el.innerText).catch(() => '')`,
    `const hasDoc = text.includes(${JSON.stringify(scenario.expectTextIncludes)})`,
    `return { url: page.url(), title, hasDoc }`,
  ].join('; ')
}

function youtubeJs(scenario) {
  const resultsUrl = JSON.stringify(
    'https://www.youtube.com/results?search_query=' + encodeURIComponent(scenario.query),
  )
  const evaluateFn = [
    `() => {`,
    `const grab = (s) => Array.from(document.querySelectorAll(s)).map(e => (e.textContent || '').trim()).filter(Boolean)`,
    `const order = ['a#video-title', 'ytd-video-renderer #video-title', 'a.yt-lockup-metadata-view-model__title', 'a[href*="watch?v="]']`,
    `for (const s of order) { const v = grab(s); if (v.length >= 3) return v.slice(0, 3) }`,
    `return grab(order[order.length - 1]).slice(0, 3)`,
    `}`,
  ].join('; ')
  return [
    `await page.goto(${resultsUrl}, { waitUntil: 'domcontentloaded' })`,
    `await page.waitForFunction(() => document.querySelectorAll('a[href*="watch?v="]').length >= 3, { timeout: 15000 }).catch(() => {})`,
    `const titles = await page.evaluate(${evaluateFn}).catch(() => [])`,
    `return { url: page.url(), titles: titles.join(' ||| ') }`,
  ].join('; ')
}

function exploreJs(scenario) {
  return [
    `await page.goto(${JSON.stringify(scenario.url)})`,
    `await page.waitForTimeout(1200)`,
    `const outline = await page.evaluate(() => {`,
    `const clean = (s) => (s || '').replace(/\\s+/g, ' ').replace(/'/g, ' ').trim().slice(0, 60)`,
    `const heads = Array.from(document.querySelectorAll('h1,h2,h3')).slice(0, 12).map(h => clean(h.innerText)).filter(Boolean)`,
    `const inter = Array.from(document.querySelectorAll('a,button,input,[role=button]')).filter(e => e.offsetParent !== null).slice(0, 20).map(e => clean(e.innerText || e.getAttribute('aria-label') || e.name || e.value)).filter(Boolean)`,
    `return { heads: heads.join(' ||| '), inter: inter.join(' ||| ') }`,
    `})`,
    `return { url: page.url(), heads: outline.heads, inter: outline.inter }`,
  ].join('; ')
}

async function exploreRun(scenario, ctx, call) {
  const r = await call(exploreJs(scenario))
  const heads = match(r.stdout, /heads:\s*'([^']*)'/)
  const inter = match(r.stdout, /inter:\s*'([^']*)'/)
  const items = [heads, inter].join(' ||| ').split(' ||| ').map((s) => s.trim()).filter(Boolean)
  ctx.note(items.join(' | '))
  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items.length} items`, data: { count: items.length } }
}

function spaJs(scenario, base) {
  return [
    `await page.goto(${JSON.stringify(base + scenario.path)})`,
    `await page.locator('button:has-text("Load items")').click()`,
    `await page.waitForSelector('li.item', { timeout: 15000 })`,
    `let items = await page.$$eval('li.item', els => els.map(e => (e.textContent || '').trim()).filter(Boolean))`,
    `return { url: page.url(), items: items.join(' ||| ') }`,
  ].join('; ')
}

async function spaRun(scenario, ctx, call) {
  const auth = ctx.auth
  if (!auth?.base) return { success: false, detail: 'sin servidor local' }
  const r = await call(spaJs(scenario, auth.base))
  const raw = match(r.stdout, /items:\s*'([^']*)'/)
  const items = raw ? raw.split(' ||| ').filter(Boolean) : []
  ctx.note(`${items.length} items`)
  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items.length} items url=${match(r.stdout, /url:\s*'([^']*)'/)}`, data: { items } }
}

async function authRoundtrip(scenario, ctx, call) {
  const auth = ctx.auth
  if (!auth?.base) return { success: false, detail: 'sin servidor de auth' }
  const secretUrl = JSON.stringify(`${auth.base}/secret`)
  const loginUrl = JSON.stringify(`${auth.base}/login`)
  const blankUrl = JSON.stringify(`${auth.base}/`)

  const loginJs = [
    `await page.goto(${loginUrl})`,
    `const a = await page.evaluate(async (u) => { const r = await fetch(u, { credentials: 'include' }); return { status: r.status, body: await r.text() } }, ${secretUrl})`,
    `return { status: a.status, body: a.body }`,
  ].join('; ')
  const a = await call(loginJs)
  const aOk = /status:\s*200/.test(a.stdout) && a.stdout.includes(auth.secret)

  await restartBrowser(ctx)

  const reopenJs = [
    `await page.goto(${blankUrl})`,
    `const b = await page.evaluate(async (u) => { const r = await fetch(u, { credentials: 'include' }); return { status: r.status, body: await r.text() } }, ${secretUrl})`,
    `return { status: b.status, body: b.body }`,
  ].join('; ')
  const b = await call(reopenJs)
  const bOk = /status:\s*200/.test(b.stdout) && b.stdout.includes(auth.secret)

  ctx.note(`login=${aOk} persist=${bOk}`)
  const success = aOk && bOk
  if (success) ctx.useful()
  return { success, detail: `login=${aOk} persist_tras_reinicio=${bOk}`, data: { aOk, bOk } }
}

async function restartBrowser(ctx) {
  const cmd = [
    `pkill -f bc-profile || true`,
    `sleep 1`,
    `P=$(npm root -g)/@opencode-ai/browser-control/extension/dist`,
    `setsid chromium --headless=new --no-first-run --no-default-browser-check --disable-gpu --user-data-dir=/tmp/bc-profile --load-extension="$P" --disable-extensions-except="$P" about:blank >/tmp/opencode/bc-chromium.log 2>&1 < /dev/null &`,
    `sleep 6`,
  ].join('; ')
  await ctx.exec('bash', ['-lc', cmd], { timeoutMs: 30000 })
}

function match(text, re) {
  const m = text.match(re)
  return m ? m[1] : ''
}
