import { existsSync } from 'node:fs'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { openMcp } from '../mcp/client.mjs'

const run = promisify(execFile)
const SERVER_BIN = 'chrome-devtools-mcp'
const SERVER_PKG = 'chrome-devtools-mcp@1.10.1'
const CHROME_CANDIDATES = [
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/brave',
]
const TITLES_FN =
  '() => Array.from(document.querySelectorAll("a#video-title, a.yt-lockup-metadata-view-model__title")).slice(0,3).map(a=>(a.textContent||"").trim()).filter(Boolean)'
const PAGE_INFO_FN = '() => ({ title: document.title, text: document.body ? document.body.innerText : "" })'
const JSON_BLOCK = /```json\n([\s\S]*?)\n```/
const SEARCH_UID = /uid=(\S+)\s+combobox "Search"/
const LOAD_BUTTON_UID = /uid=(\S+)\s+button "Load items"/
const PAGE_ID = /^(\d+):/m
const STRUCT_ITEM = /uid=\S+\s+(?:link|heading)\b/gi
const ITEMS_FN =
  '() => Array.from(document.querySelectorAll("li.item")).map(li=>(li.textContent||"").trim()).filter(Boolean)'

export const name = 'chrome-devtools-mcp'
export const kind = 'mcp'
export const realProfile = false
export const notes =
  'Google chrome-devtools-mcp 1.10.1: MCP stdio sobre CDP, headless+isolated. Extraccion barata con evaluate_script; snapshot a11y por uid solo para interactuar. Extensible a perf/red: performance_start_trace, performance_stop_trace, performance_analyze_insight, list_network_requests, get_network_request, lighthouse_audit. Roundtrips se registran via ctx.exec porque las llamadas MCP no pasan por el medidor del harness.'

let launch = null

function chromePath() {
  for (const p of CHROME_CANDIDATES) {
    if (existsSync(p)) return p
  }
  return process.env.CHROME_PATH || ''
}

function serverArgs() {
  const args = ['--headless', '--isolated']
  const bin = chromePath()
  if (bin) args.push('--executablePath', bin)
  return args
}

async function probe(command, args) {
  try {
    await run(command, [...args, '--version'], { timeout: 30000 })
    return true
  } catch {
    return false
  }
}

async function resolveLaunch() {
  if (launch) return launch
  if (await probe(SERVER_BIN, [])) {
    launch = { command: SERVER_BIN, args: serverArgs() }
  } else if (await probe('npx', ['-y', SERVER_PKG])) {
    launch = { command: 'npx', args: ['-y', SERVER_PKG, ...serverArgs()] }
  }
  return launch
}

export async function available() {
  return Boolean(await resolveLaunch())
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function parseJson(text) {
  const m = text.match(JSON_BLOCK)
  if (!m) return null
  try {
    return JSON.parse(m[1])
  } catch {
    return null
  }
}

function firstPageId(text) {
  const m = text.match(PAGE_ID)
  return m ? Number(m[1]) : null
}

function searchUid(text) {
  const m = text.match(SEARCH_UID)
  return m ? m[1] : null
}

function loadButtonUid(text) {
  const m = text.match(LOAD_BUTTON_UID)
  return m ? m[1] : null
}

function scenarioUrl(scenario, ctx) {
  if (scenario.url) return scenario.url
  if (scenario.path && ctx.auth?.base) return ctx.auth.base + scenario.path
  return null
}

function countItems(text) {
  const m = text.match(STRUCT_ITEM)
  return m ? m.length : 0
}

async function openPage(ctx, call, url) {
  const listed = await call('list_pages', {})
  const pageId = firstPageId(listed.text)
  if (pageId === null) {
    const created = await call('new_page', { url })
    return firstPageId(created.text)
  }
  await call('navigate_page', { pageId, type: 'url', url, timeout: 45000 })
  return pageId
}

async function publicNav(scenario, ctx, call) {
  const pageId = await openPage(ctx, call, scenario.url)
  if (pageId === null) return { success: false, detail: 'sin pageId', data: null }

  const probe = await call('evaluate_script', { pageId, waitForStableDom: false, function: PAGE_INFO_FN })
  const info = parseJson(probe.text) ?? {}
  const title = info.title ?? ''
  const text = info.text ?? ''

  const snap = await call('take_snapshot', { pageId })

  const success = title.includes(scenario.expectTitle) || text.includes(scenario.expectTextIncludes)
  if (success) ctx.useful()
  return {
    success,
    detail: `title="${title}" snapshot_chars=${snap.text.length}`,
    data: { title, snapshot_chars: snap.text.length },
  }
}

async function youtubeLight(scenario, ctx, call) {
  const pageId = await openPage(ctx, call, scenario.url)
  if (pageId === null) return { success: false, detail: 'sin pageId', data: null }

  let uid = null
  for (let i = 0; i < 4 && !uid; i += 1) {
    const snap = await call('take_snapshot', { pageId })
    uid = searchUid(snap.text)
    if (!uid) await wait(1500)
  }
  if (!uid) return { success: false, detail: 'sin input de busqueda', data: null }

  await call('fill', { pageId, uid, value: scenario.query })
  await call('press_key', { pageId, key: 'Enter' })

  let titles = []
  for (let i = 0; i < 8; i += 1) {
    await wait(1500)
    const res = await call('evaluate_script', { pageId, waitForStableDom: false, function: TITLES_FN })
    const parsed = parseJson(res.text)
    if (Array.isArray(parsed)) titles = parsed
    if (titles.length >= scenario.minTitles) break
  }

  const success = titles.length >= scenario.minTitles
  if (success) ctx.useful()
  return { success, detail: `${titles.length} titulos`, data: { titles } }
}

async function explore(scenario, ctx, call) {
  const pageId = await openPage(ctx, call, scenario.url)
  if (pageId === null) return { success: false, detail: 'sin pageId', data: null }

  let items = 0
  let chars = 0
  for (let i = 0; i < 6; i += 1) {
    const snap = await call('take_snapshot', { pageId })
    chars = snap.text.length
    items = countItems(snap.text)
    if (items >= scenario.minItems) break
    await wait(1500)
  }

  const success = items >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items} items snapshot_chars=${chars}`, data: { items, snapshot_chars: chars } }
}

async function spaTask(scenario, ctx, call) {
  const url = scenarioUrl(scenario, ctx)
  if (!url) return { success: false, detail: 'sin url local', data: null }

  const pageId = await openPage(ctx, call, url)
  if (pageId === null) return { success: false, detail: 'sin pageId', data: null }

  let uid = null
  for (let i = 0; i < 6 && !uid; i += 1) {
    const snap = await call('take_snapshot', { pageId })
    uid = loadButtonUid(snap.text)
    if (!uid) await wait(1000)
  }
  if (!uid) return { success: false, detail: 'sin boton "Load items"', data: null }

  await call('click', { pageId, uid })

  let items = []
  for (let i = 0; i < 8; i += 1) {
    await wait(1200)
    const res = await call('evaluate_script', { pageId, waitForStableDom: false, function: ITEMS_FN })
    const parsed = parseJson(res.text)
    if (Array.isArray(parsed)) items = parsed
    if (items.length >= scenario.minItems) break
  }

  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items.length} items`, data: { items } }
}

export async function runScenario(scenario, ctx) {  const resolved = await resolveLaunch()
  if (!resolved) return { success: false, detail: 'chrome-devtools-mcp no resuelve', data: null }

  const mcp = await openMcp({
    command: resolved.command,
    args: resolved.args,
    env: { CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS: '1' },
  })
  const call = async (tool, toolArgs) => {
    await ctx.exec('true', [], { timeoutMs: 5000 })
    ctx.note(JSON.stringify(toolArgs ?? {}))
    const res = await mcp.call(tool, toolArgs)
    ctx.note(res.text)
    return res
  }

  try {
    if (scenario.id === 'public_nav') return await publicNav(scenario, ctx, call)
    if (scenario.id === 'youtube_light') return await youtubeLight(scenario, ctx, call)
    if (scenario.id === 'spa_task') return await spaTask(scenario, ctx, call)
    if (scenario.id.startsWith('explore')) return await explore(scenario, ctx, call)
    return { success: false, detail: 'escenario no soportado', data: null }
  } finally {
    await mcp.close()
  }
}
