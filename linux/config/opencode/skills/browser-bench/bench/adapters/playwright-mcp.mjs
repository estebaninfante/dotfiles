import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { existsSync } from 'node:fs'
import { openMcp } from '../mcp/client.mjs'

const run = promisify(execFile)

const VERSION = '0.0.83'
const PKG = `@playwright/mcp@${VERSION}`

export const name = 'playwright-mcp'
export const kind = 'mcp'
export const realProfile = false
export const notes =
  'Microsoft @playwright/mcp baseline: stdio MCP, headless Chromium temp profile. A11y snapshot compacto (example.com ~1.2k chars, youtube home ~0.5k) pero browser_evaluate es mas barato para extraccion. Perfil real posible con --extension (Chrome/Edge + Playwright Extension) o --cdp-endpoint, no por defecto. Refs a11y [ref=eN] se invalidan al navegar. roundtrips = tool calls MCP (espejados al harness via ctx.exec true).'

function findExecutable() {
  const candidates = [
    process.env.PLAYWRIGHT_MCP_EXECUTABLE,
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
  ]
  return candidates.find((p) => p && existsSync(p)) ?? null
}

function serverArgs() {
  const args = ['-y', PKG, '--headless']
  const exe = findExecutable()
  if (exe) args.push('--executable-path', exe, '--no-sandbox')
  return args
}

export async function available() {
  try {
    const { stdout } = await run('npx', ['-y', PKG, '--version'], { timeout: 60000 })
    return stdout.includes(VERSION)
  } catch {
    return false
  }
}

function extractJson(text, open, close) {
  const start = text.indexOf(open)
  if (start < 0) return null
  let depth = 0
  let inStr = false
  let esc = false
  for (let i = start; i < text.length; i += 1) {
    const c = text[i]
    if (inStr) {
      if (esc) esc = false
      else if (c === '\\') esc = true
      else if (c === '"') inStr = false
    } else if (c === '"') {
      inStr = true
    } else if (c === open) {
      depth += 1
    } else if (c === close) {
      depth -= 1
      if (depth === 0) {
        try {
          return JSON.parse(text.slice(start, i + 1))
        } catch {
          return null
        }
      }
    }
  }
  return null
}

function pickSearchRef(text) {
  const m = text.match(/combobox[^\n]*\[ref=(e\d+)\]/)
  return m ? m[1] : null
}

function pickButtonRef(text, label) {
  const re = new RegExp(`button "${label}"[^\\n]*\\[ref=(e\\d+)\\]`)
  const m = text.match(re)
  return m ? m[1] : null
}

const TITLES_FN =
  "() => Array.from(document.querySelectorAll('a#video-title, a.yt-lockup-metadata-view-model__title, ytd-video-renderer #video-title')).slice(0, 3).map((a) => (a.textContent || '').trim()).filter(Boolean)"

const PAGE_FN =
  "() => ({ title: document.title, text: (document.body && document.body.innerText || '').slice(0, 2000) })"

const ITEMS_FN =
  "() => { const vis = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' }; const out = []; const seen = new Set(); for (const el of document.querySelectorAll('h1,h2,h3,a,button,input')) { if (!vis(el)) continue; const k = el.tagName + '|' + (el.textContent || el.value || '').trim().slice(0, 80); if (seen.has(k)) continue; seen.add(k); out.push(k); } return out; }"

const SPA_ITEMS_FN =
  "() => Array.from(document.querySelectorAll('li.item')).map((e) => (e.textContent || '').trim()).filter(Boolean)"

function countRefs(text) {
  const m = text.match(/\[ref=e\d+\]/g)
  return m ? m.length : 0
}

async function publicNav(scenario, ctx, call) {
  const nav = await call('browser_navigate', { url: scenario.url })
  ctx.note(nav.text)

  const ev = await call('browser_evaluate', { function: PAGE_FN })
  ctx.note(ev.text)
  const parsed = extractJson(ev.text, '{', '}')
  const title = parsed?.title ?? ''
  const text = parsed?.text ?? ''

  const snap = await call('browser_snapshot', {})
  ctx.note(snap.text)

  const success = title.includes(scenario.expectTitle) || text.includes(scenario.expectTextIncludes)
  if (success) ctx.useful()
  return {
    success,
    detail: `title="${title}" eval_chars=${ev.text.length} snap_chars=${snap.text.length}`,
    data: { title, text: text.slice(0, 200), snapshotChars: snap.text.length },
  }
}

async function youtubeLight(scenario, ctx, call) {
  const nav = await call('browser_navigate', { url: scenario.url })
  ctx.note(nav.text)

  let ref = null
  let snapChars = 0
  for (let i = 0; i < 3 && !ref; i += 1) {
    const snap = await call('browser_snapshot', {})
    snapChars = snap.text.length
    ctx.note(snap.text)
    ref = pickSearchRef(snap.text)
    if (!ref) await call('browser_wait_for', { time: 1 })
  }
  if (!ref) return { success: false, detail: `sin ref de busqueda snap_chars=${snapChars}`, data: null }

  const typed = await call('browser_type', { element: 'Search', target: ref, text: scenario.query, submit: true })
  ctx.note(typed.text)

  await call('browser_wait_for', { time: 3 })

  let titles = []
  for (let i = 0; i < 5; i += 1) {
    const ev = await call('browser_evaluate', { function: TITLES_FN })
    ctx.note(ev.text)
    const arr = extractJson(ev.text, '[', ']')
    titles = Array.isArray(arr) ? arr.filter((t) => typeof t === 'string' && t.trim()) : []
    if (titles.length >= scenario.minTitles) break
    await call('browser_wait_for', { time: 1 })
  }

  const success = titles.length >= scenario.minTitles
  if (success) ctx.useful()
  return { success, detail: `${titles.length} titulos ref=${ref}`, data: { titles } }
}

async function explore(scenario, ctx, call) {
  const nav = await call('browser_navigate', { url: scenario.url })
  ctx.note(nav.text)

  const snap = await call('browser_snapshot', {})
  ctx.note(snap.text)
  let items = countRefs(snap.text)
  let mode = 'snapshot'

  if (items < scenario.minItems) {
    const ev = await call('browser_evaluate', { function: ITEMS_FN })
    ctx.note(ev.text)
    const arr = extractJson(ev.text, '[', ']')
    if (Array.isArray(arr) && arr.length > items) {
      items = arr.length
      mode = 'evaluate'
    }
  }

  const success = items >= scenario.minItems
  if (success) ctx.useful()
  return {
    success,
    detail: `${items} items via ${mode} snap_chars=${snap.text.length}`,
    data: { items, mode, snapshotChars: snap.text.length },
  }
}

async function spaTask(scenario, ctx, call) {
  const base = ctx.auth?.base
  if (!base) return { success: false, detail: 'sin servidor local', data: null }
  const url = base + scenario.path

  const nav = await call('browser_navigate', { url })
  ctx.note(nav.text)

  let ref = null
  let snapChars = 0
  for (let i = 0; i < 4 && !ref; i += 1) {
    const snap = await call('browser_snapshot', {})
    snapChars = snap.text.length
    ctx.note(snap.text)
    ref = pickButtonRef(snap.text, 'Load items')
    if (!ref) await call('browser_wait_for', { time: 1 })
  }
  if (!ref) return { success: false, detail: `sin ref de boton snap_chars=${snapChars}`, data: null }

  const clicked = await call('browser_click', { element: 'Load items', target: ref })
  ctx.note(clicked.text)

  let items = []
  for (let i = 0; i < 5; i += 1) {
    await call('browser_wait_for', { time: 1 })
    const ev = await call('browser_evaluate', { function: SPA_ITEMS_FN })
    ctx.note(ev.text)
    const arr = extractJson(ev.text, '[', ']')
    items = Array.isArray(arr) ? arr.filter((t) => typeof t === 'string' && t.trim()) : []
    if (items.length >= scenario.minItems) break
  }

  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items.length} items ref=${ref}`, data: { items } }
}

export async function runScenario(scenario, ctx) {
  let mcp = null
  const mirror = () => ctx.exec('/usr/bin/true', [], { timeoutMs: 5000 })
  const call = async (tool, args) => {
    ctx.note(JSON.stringify(args))
    await mirror()
    return mcp.call(tool, args)
  }
  try {
    mcp = await openMcp({ command: 'npx', args: serverArgs() })
    if (!mcp.toolNames.includes('browser_navigate')) {
      return { success: false, detail: `server sin browser_navigate (${mcp.toolNames.length} tools)`, data: null }
    }
    if (scenario.id === 'public_nav') return await publicNav(scenario, ctx, call)
    if (scenario.id === 'youtube_light') return await youtubeLight(scenario, ctx, call)
    if (scenario.id === 'spa_task') return await spaTask(scenario, ctx, call)
    if (scenario.id.startsWith('explore')) return await explore(scenario, ctx, call)
    return { success: false, detail: 'escenario no soportado', data: null }
  } catch (e) {
    return { success: false, detail: `error mcp: ${e?.message ?? e}`, data: null }
  } finally {
    if (mcp) await mcp.close()
  }
}
