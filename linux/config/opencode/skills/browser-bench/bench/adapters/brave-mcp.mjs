import { existsSync } from 'node:fs'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { openMcp } from '../mcp/client.mjs'

const run = promisify(execFile)
const SERVER_BIN = 'brave-mcp'
const SERVER_PKG = 'brave-mcp@1.9.0'
const BRAVE_CANDIDATES = ['/usr/bin/brave', '/usr/bin/brave-browser', '/opt/brave.com/brave/brave']
const TITLES_FN =
  '() => Array.from(document.querySelectorAll("a#video-title, a.yt-lockup-metadata-view-model__title")).slice(0,3).map(a=>(a.textContent||"").trim()).filter(Boolean)'
const PAGE_INFO_FN = '() => ({ title: document.title, text: document.body ? document.body.innerText : "" })'
const SPA_ITEMS_FN =
  '() => Array.from(document.querySelectorAll("li.item")).map(e=>(e.textContent||"").trim()).filter(Boolean)'
const JSON_BLOCK = /```json\n([\s\S]*?)\n```/
const SEARCH_UID = /uid=(\S+)\s+combobox "Search"/
const LOAD_BUTTON_UID = /uid=(\S+)\s+button "Load items"/
const PAGE_ID = /^(\d+):/m
const UID_REF = /uid=\S+/g
const A11Y_ROLE =
  /\b(?:link|heading|button|textbox|combobox|searchbox|checkbox|radio|menuitem|tab|listitem|navigation)\b/gi

export const name = 'brave-mcp'
export const kind = 'mcp'
export const realProfile = true
export const notes =
  'triuzzi brave-devtools-mcp 1.9.0: fork 0-commits-behind de chrome-devtools-mcp, Brave-native (Release/Beta/Nightly). 30 tools incl. perf/red/heap. Attach a Brave real via --browserUrl/--autoConnect; aqui se midio headless+isolated. Extraccion barata con evaluate_script.'

let launch = null

function bravePath() {
  for (const p of BRAVE_CANDIDATES) {
    if (existsSync(p)) return p
  }
  return process.env.BRAVE_PATH || ''
}

function serverArgs() {
  const args = ['--headless', '--isolated']
  const bin = bravePath()
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

function countItems(text) {
  const refs = text.match(UID_REF)
  if (refs && refs.length) return refs.length
  const roles = text.match(A11Y_ROLE)
  return roles ? roles.length : 0
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
  ctx.note(text)

  const snap = await call('take_snapshot', { pageId })
  ctx.note(snap.text)

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
    ctx.note(snap.text)
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
    ctx.note(res.text)
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
  let snapshotChars = 0
  for (let i = 0; i < 5; i += 1) {
    const snap = await call('take_snapshot', { pageId })
    ctx.note(snap.text)
    snapshotChars = snap.text.length
    items = countItems(snap.text)
    if (items >= scenario.minItems) break
    await wait(1500)
  }

  const success = items >= scenario.minItems
  if (success) ctx.useful()
  return {
    success,
    detail: `${items} items snapshot_chars=${snapshotChars}`,
    data: { items, snapshot_chars: snapshotChars },
  }
}

async function spaTask(scenario, ctx, call, base) {
  const url = base + scenario.path
  const pageId = await openPage(ctx, call, url)
  if (pageId === null) return { success: false, detail: 'sin pageId', data: null }

  let uid = null
  for (let i = 0; i < 4 && !uid; i += 1) {
    const snap = await call('take_snapshot', { pageId })
    ctx.note(snap.text)
    uid = loadButtonUid(snap.text)
    if (!uid) await wait(1000)
  }
  if (!uid) return { success: false, detail: 'sin boton Load items', data: null }

  await call('click', { pageId, uid })

  let items = []
  for (let i = 0; i < 6; i += 1) {
    await wait(1200)
    const res = await call('evaluate_script', { pageId, waitForStableDom: false, function: SPA_ITEMS_FN })
    ctx.note(res.text)
    const parsed = parseJson(res.text)
    if (Array.isArray(parsed)) items = parsed
    if (items.length >= scenario.minItems) break
  }

  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return { success, detail: `${items.length} items uid=${uid}`, data: { items } }
}

export async function runScenario(scenario, ctx) {
  const resolved = await resolveLaunch()
  if (!resolved) return { success: false, detail: 'brave-mcp no resuelve', data: null }

  const mcp = await openMcp({ command: resolved.command, args: resolved.args })
  const call = async (tool, toolArgs) => {
    ctx.note(JSON.stringify(toolArgs))
    await ctx.exec('true', [], { timeoutMs: 5000 })
    return mcp.call(tool, toolArgs)
  }

  try {
    if (scenario.id === 'public_nav') return await publicNav(scenario, ctx, call)
    if (scenario.id === 'youtube_light') return await youtubeLight(scenario, ctx, call)
    if (scenario.id.startsWith('explore')) return await explore(scenario, ctx, call)
    if (scenario.id === 'spa_task') return await spaTask(scenario, ctx, call, ctx.auth?.base ?? '')
    return { success: false, detail: 'escenario no soportado', data: null }
  } finally {
    await mcp.close()
  }
}
