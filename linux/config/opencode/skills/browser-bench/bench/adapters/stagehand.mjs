import { existsSync } from 'node:fs'

export const name = 'stagehand'
export const kind = 'lib'
export const realProfile = false
export const notes =
  'Browserbase Stagehand v4.1.0 (npm @browserbasehq/stagehand), SDK TS/JS puro. Sin API key se usa el API LOCAL determinista: localBrowser.launch (chromium headless) + Stagehand.create + page propia con goto/title/evaluate/locator/fill/keyPress/waitForTimeout. act()/extract()/observe() requieren LLM key (NO configurada), por eso no se usan y solo mejorarian el score de forma cualitativa. roundtrips del harness = 0: no hay backend externo, todo es in-process.'

const CHROMIUM_CANDIDATES = [
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
]

const LAUNCH_ARGS = ['--no-sandbox', '--disable-dev-shm-usage']

const BODY_TEXT_EXPR = () => (document.body ? document.body.innerText : '')

const TITLES_EXPR = () =>
  Array.from(
    document.querySelectorAll('a#video-title, a.yt-lockup-metadata-view-model__title'),
  )
    .slice(0, 3)
    .map((el) => (el.textContent || '').trim())
    .filter(Boolean)

const EXPLORE_EXPR = () =>
  Array.from(document.querySelectorAll('h1, h2, h3, a, button, input'))
    .filter((el) => {
      if (!el.getClientRects().length) return false
      const style = window.getComputedStyle(el)
      return style.visibility !== 'hidden' && style.display !== 'none'
    })
    .map((el) => {
      if (el.tagName.toLowerCase() === 'input') {
        return (
          el.getAttribute('aria-label') ||
          el.getAttribute('placeholder') ||
          el.getAttribute('name') ||
          el.getAttribute('type') ||
          ''
        )
      }
      return (
        el.getAttribute('aria-label') ||
        el.textContent ||
        el.getAttribute('title') ||
        ''
      )
    })
    .map((text) => text.replace(/\s+/g, ' ').trim().slice(0, 120))
    .filter((text) => text.length > 1)
    .filter((text, index, list) => list.indexOf(text) === index)
    .slice(0, 80)

const SPA_ITEMS_EXPR = () =>
  Array.from(document.querySelectorAll('li.item'))
    .map((el) => (el.textContent || '').trim())
    .filter(Boolean)

const SPA_BUTTON_SELECTOR = 'text=Load items'

function chromiumPath() {
  for (const candidate of CHROMIUM_CANDIDATES) {
    if (existsSync(candidate)) return candidate
  }
  return null
}

function withDeadline(promise, ms) {
  let timer
  const guard = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout ${ms}ms`)), ms)
  })
  return Promise.race([promise, guard]).finally(() => clearTimeout(timer))
}

function launchOptions() {
  const executablePath = chromiumPath()
  if (!executablePath) throw new Error('chromium no encontrado')
  return { headless: true, executablePath, args: LAUNCH_ARGS }
}

async function publicNav(scenario, ctx, page) {
  await page.goto(scenario.url, { waitUntil: 'domcontentloaded' })
  const title = await page.title()
  ctx.note(BODY_TEXT_EXPR.toString())
  const text = await page.evaluate(BODY_TEXT_EXPR)
  ctx.note(title)
  ctx.note(text)
  const success =
    title.includes(scenario.expectTitle) ||
    text.includes(scenario.expectTextIncludes)
  if (success) ctx.useful()
  return {
    success,
    detail: `title="${title}" textLen=${text.length}`,
    data: { title, textLen: text.length },
  }
}

async function youtubeLight(scenario, ctx, page) {
  await page.goto(scenario.url, { waitUntil: 'domcontentloaded' })
  await page.locator('input[name="search_query"]').fill(scenario.query)
  await page.keyPress('Enter')
  ctx.note(TITLES_EXPR.toString())
  let titles = []
  for (let i = 0; i < 25; i += 1) {
    titles = await page.evaluate(TITLES_EXPR)
    if (titles.length >= scenario.minTitles) break
    await page.waitForTimeout(800)
  }
  ctx.note(titles.join('\n'))
  const success = titles.length >= scenario.minTitles
  if (success) ctx.useful()
  const url = await page.url()
  return {
    success,
    detail: `${titles.length} titulos url=${url}`,
    data: { titles, url },
  }
}

async function spaTask(scenario, ctx, page) {
  const auth = ctx.auth
  const base = scenario.url || (auth?.base ? auth.base + scenario.path : '')
  if (!base) return { success: false, detail: 'sin servidor local', data: null }
  await page.goto(base, { waitUntil: 'domcontentloaded' })
  ctx.note(SPA_BUTTON_SELECTOR)
  await page.locator(SPA_BUTTON_SELECTOR).first().click()
  ctx.note(SPA_ITEMS_EXPR.toString())
  let items = []
  for (let i = 0; i < 8; i += 1) {
    items = await page.evaluate(SPA_ITEMS_EXPR)
    if (items.length >= scenario.minItems) break
    await page.waitForTimeout(700)
  }
  ctx.note(items.join('\n'))
  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  const url = await page.url()
  return {
    success,
    detail: `${items.length} items (min ${scenario.minItems}) url=${url}`,
    data: { items, url },
  }
}

async function explore(scenario, ctx, page) {
  await page.goto(scenario.url, { waitUntil: 'domcontentloaded' })
  await page.waitForTimeout(1200)
  ctx.note(EXPLORE_EXPR.toString())
  let items = []
  for (let i = 0; i < 8; i += 1) {
    items = await page.evaluate(EXPLORE_EXPR)
    if (items.length >= scenario.minItems) break
    await page.waitForTimeout(700)
  }
  ctx.note(items.join('\n'))
  const success = items.length >= scenario.minItems
  if (success) ctx.useful()
  return {
    success,
    detail: `${items.length} items (min ${scenario.minItems})`,
    data: { items },
  }
}

async function dispatch(scenario, ctx, page) {
  if (scenario.id === 'public_nav') return publicNav(scenario, ctx, page)
  if (scenario.id === 'youtube_light') return youtubeLight(scenario, ctx, page)
  if (scenario.id === 'spa_task') return spaTask(scenario, ctx, page)
  if (scenario.id.startsWith('explore')) return explore(scenario, ctx, page)
  return { success: false, detail: 'escenario no soportado', data: null }
}

export async function available() {
  try {
    if (!chromiumPath()) return false
    const { localBrowser } = await import('@browserbasehq/stagehand')
    const browser = await localBrowser.launch(launchOptions())
    await browser.close()
    return true
  } catch {
    return false
  }
}

export async function runScenario(scenario, ctx) {
  let mod
  try {
    mod = await import('@browserbasehq/stagehand')
  } catch (e) {
    return { success: false, detail: `import fallido: ${e.message}`, data: null }
  }
  let browser
  try {
    browser = await mod.localBrowser.launch(launchOptions())
  } catch (e) {
    return { success: false, detail: `launch fallido: ${e.message}`, data: null }
  }
  let stagehand
  try {
    stagehand = await mod.Stagehand.create({ browser })
    const [page] = await browser.context.pages()
    return await withDeadline(
      dispatch(scenario, ctx, page),
      scenario.timeoutMs ?? 90000,
    )
  } finally {
    await stagehand?.close?.().catch(() => {})
    await browser.close().catch(() => {})
  }
}
