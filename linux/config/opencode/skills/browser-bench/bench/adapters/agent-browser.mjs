import { execFile } from 'node:child_process'
import { promisify } from 'node:util'

const run = promisify(execFile)
const BIN = 'agent-browser'

export const name = 'agent-browser'
export const kind = 'cli+mcp'
export const realProfile = true
export const notes =
  'A11y refs (@eN), snapshot --delta, batch, profile copy read-only. 43k stars, activo.'

export async function available() {
  try {
    await run(BIN, ['--version'], { timeout: 10000 })
    return true
  } catch {
    return false
  }
}

function makeSession() {
  return `bench-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`
}

export async function runScenario(scenario, ctx) {
  const session = makeSession()
  const env = { ...process.env, AGENT_BROWSER_SESSION: session }
  const call = (args, opts = {}) =>
    ctx.exec(BIN, args, { env, timeoutMs: opts.timeoutMs ?? scenario.timeoutMs })

  try {
    const target = scenario.url || (ctx.auth?.base ? ctx.auth.base + scenario.path : '')
    await call(['open', target])
    let url = await settle(call, target)
    if (!url) {
      await call(['open', target])
      url = await settle(call, target)
    }
    if (!url) return { success: false, detail: 'navegacion fallida' }
    await call(['wait', '2000']).catch(() => {})

    if (scenario.id === 'public_nav') return await publicNav(scenario, ctx, call)
    if (scenario.id === 'youtube_light') return await youtubeLight(scenario, ctx, call)
    if (scenario.id.startsWith('explore')) return await explore(scenario, ctx, call)
    if (scenario.id === 'spa_task') return await spaTask(scenario, ctx, call)
    return { success: false, detail: 'escenario no soportado' }
  } finally {
    await call(['close']).catch(() => {})
  }
}

async function settle(call, target) {
  const host = new URL(target).host
  for (let i = 0; i < 6; i += 1) {
    const r = await call(['get', 'url'])
    const url = r.stdout.trim()
    if (url && url.includes(host)) return url
    await call(['wait', '500']).catch(() => {})
  }
  return ''
}

async function publicNav(scenario, ctx, call) {
  const title = await call(['get', 'title'])
  ctx.note(title.stdout)
  const text = await call(['read', scenario.url])
  ctx.note(text.stdout)
  const wantTitle = title.stdout.trim().includes(scenario.expectTitle)
  const wantText = text.stdout.includes(scenario.expectTextIncludes)
  const success = wantTitle || wantText
  if (success) ctx.useful()
  return { success, detail: `title="${title.stdout.trim()}"`, data: { title: title.stdout.trim() } }
}

const TITLES_JS =
  "Array.from(document.querySelectorAll('a#video-title, a.yt-lockup-metadata-view-model__title')).slice(0,3).map(a=>a.textContent.trim())"

async function youtubeLight(scenario, ctx, call) {
  ctx.note(TITLES_JS)
  let ref = null
  for (let i = 0; i < 3 && !ref; i += 1) {
    const snap = await call(['snapshot', '-i'])
    ctx.note(snap.stdout)
    ref = pickSearchRef(snap.stdout)
    if (!ref) await call(['wait', '1500']).catch(() => {})
  }
  if (!ref) return { success: false, detail: 'sin ref de busqueda' }

  await call(['fill', `@${ref}`, scenario.query])
  await call(['press', 'Enter'])
  await call(['wait', '2500']).catch(() => {})

  let list = []
  for (let i = 0; i < 6; i += 1) {
    const titles = await call(['eval', TITLES_JS])
    ctx.note(titles.stdout)
    list = parseTitles(titles.stdout)
    if (list.length >= scenario.minTitles) break
    await call(['wait', '900']).catch(() => {})
  }
  const success = list.length >= scenario.minTitles
  if (success) ctx.useful()
  const where = (await call(['get', 'url'])).stdout.trim()
  return { success, detail: `${list.length} titulos ref=${ref} url=${where}`, data: { titles: list } }
}

async function explore(scenario, ctx, call) {
  let items = []
  for (let i = 0; i < 4; i += 1) {
    const snap = await call(['snapshot', '-i'])
    ctx.note(snap.stdout)
    items = Array.from(new Set(snap.stdout.match(/ref=e\d+/g) ?? []))
    if (items.length >= scenario.minItems) break
    await call(['wait', '1200']).catch(() => {})
  }
  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items.length} interactive refs`, data: { count: items.length } }
}

function parseTitles(out) {
  const raw = out.trim()
  try {
    const v = JSON.parse(raw)
    return Array.isArray(v) ? v : []
  } catch {
    return []
  }
}

function pickSearchRef(text) {
  const m = text.match(/combobox "Search"[^\n]*ref=(e\d+)/)
  return m ? m[1] : null
}

const SPA_ITEMS_JS =
  "Array.from(document.querySelectorAll('li.item')).map(e => (e.textContent || '').trim()).filter(Boolean)"

async function spaTask(scenario, ctx, call) {
  let ref = null
  for (let i = 0; i < 4 && !ref; i += 1) {
    const snap = await call(['snapshot', '-i'])
    ctx.note(snap.stdout)
    ref = pickButtonRef(snap.stdout, 'Load items')
    if (!ref) await call(['wait', '1000']).catch(() => {})
  }
  if (!ref) return { success: false, detail: 'sin ref de boton' }

  await call(['click', `@${ref}`])
  ctx.note(SPA_ITEMS_JS)
  let list = []
  for (let i = 0; i < 6; i += 1) {
    const items = await call(['eval', SPA_ITEMS_JS])
    ctx.note(items.stdout)
    list = parseTitles(items.stdout)
    if (list.length >= scenario.minItems) break
    await call(['wait', '800']).catch(() => {})
  }
  const success = list.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${list.length} items ref=${ref}`, data: { items: list } }
}

function pickButtonRef(text, label) {
  const re = new RegExp(`button "${label}"[^\\n]*ref=(e\\d+)`)
  const m = text.match(re)
  return m ? m[1] : null
}
