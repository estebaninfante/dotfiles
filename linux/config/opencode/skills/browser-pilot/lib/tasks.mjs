export const tasks = {
  playLatestYouTube({ selectors, args }) {
    const channel = args.channel
    if (!channel) throw new Error('falta --channel')
    const sel = JSON.stringify(selectors.youtube.selectors)
    const url = `https://www.youtube.com/@${channel}/videos`
    return [
      `const sel = ${sel}`,
      `await page.goto(${JSON.stringify(url)}, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForFunction((s) => document.querySelectorAll(s.lockupItem).length >= 3, sel, { timeout: 25000 })`,
      `const first = await page.evaluate((s) => { const items = Array.from(document.querySelectorAll(s.lockupItem)); for (const it of items) { const a = it.querySelector(s.lockupLink); const t = it.querySelector(s.lockupTitle); if (a && t) return { title: t.textContent.trim(), url: new URL(a.getAttribute('href'), location.origin).href } } return null }, sel)`,
      `if (!first) return JSON.stringify({ ok: false, error: 'sin videos' })`,
      `await page.goto(first.url, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForSelector(sel.player, { timeout: 20000 })`,
      `const state = await (async () => { for (let i = 0; i < 8; i += 1) { const s = await page.evaluate(() => { const v = document.querySelector('video'); if (!v) return { playing: false, currentTime: 0 }; if (v.paused) { const b = document.querySelector('.ytp-large-play-button, .ytp-play-button'); if (b) b.click() } return { playing: !v.paused, currentTime: v.currentTime } }); if (s.playing) return s; await page.waitForTimeout(700) } return { playing: false, currentTime: 0 } })()`,
      `return JSON.stringify({ ok: true, channel: ${JSON.stringify(channel)}, title: first.title, url: first.url, playing: state.playing, currentTime: state.currentTime })`,
    ].join('\n')
  },

  searchPlayYouTube({ selectors, args }) {
    const query = args.query
    if (!query) throw new Error('falta --query')
    const sel = JSON.stringify(selectors.youtube.selectors)
    const url = `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`
    return [
      `const sel = ${sel}`,
      `await page.goto(${JSON.stringify(url)}, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForFunction((s) => document.querySelectorAll(s.resultsNav).length >= 1 || document.querySelectorAll(s.lockupItem).length >= 1, sel, { timeout: 25000 })`,
      `const first = await page.evaluate((s) => { let a = document.querySelector(s.resultsNav); if (a && a.getAttribute('href')) return { title: (a.textContent || '').trim(), url: new URL(a.getAttribute('href'), location.origin).href }; const it = document.querySelector(s.lockupItem); if (!it) return null; const l = it.querySelector(s.lockupLink); const t = it.querySelector(s.lockupTitle); return l ? { title: t ? t.textContent.trim() : '', url: new URL(l.getAttribute('href'), location.origin).href } : null }, sel)`,
      `if (!first) return JSON.stringify({ ok: false, error: 'sin resultados' })`,
      `await page.goto(first.url, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForSelector(sel.player, { timeout: 20000 })`,
      `const state = await (async () => { for (let i = 0; i < 8; i += 1) { const s = await page.evaluate(() => { const v = document.querySelector('video'); if (!v) return { playing: false, currentTime: 0 }; if (v.paused) { const b = document.querySelector('.ytp-large-play-button, .ytp-play-button'); if (b) b.click() } return { playing: !v.paused, currentTime: v.currentTime } }); if (s.playing) return s; await page.waitForTimeout(700) } return { playing: false, currentTime: 0 } })()`,
      `return JSON.stringify({ ok: true, query: ${JSON.stringify(query)}, title: first.title, url: first.url, playing: state.playing, currentTime: state.currentTime })`,
    ].join('\n')
  },

  playLatestChannelTopic({ selectors, args }) {
    const channel = args.channel
    const query = args.query
    if (!channel) throw new Error('falta --channel')
    if (!query) throw new Error('falta --query')
    const sel = JSON.stringify(selectors.youtube.selectors)
    const tokens = JSON.stringify(query.toLowerCase().split(/\s+/).filter(Boolean))
    return [
      `const sel = ${sel}`,
      `const tokens = ${tokens}`,
      `await page.goto(${JSON.stringify('https://www.youtube.com/@' + channel)}, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForSelector('meta[itemprop="identifier"]', { state: 'attached', timeout: 20000 })`,
      `const channelId = await page.evaluate(() => { const m = document.querySelector('meta[itemprop="identifier"]') || document.querySelector('meta[itemprop="channelId"]'); return m ? m.content : null })`,
      `if (!channelId) return JSON.stringify({ ok: false, error: 'sin channelId' })`,
      `const xml = await page.evaluate(async (id) => { const r = await fetch('https://www.youtube.com/feeds/videos.xml?channel_id=' + id); return r.ok ? await r.text() : '' }, channelId)`,
      `if (!xml) return JSON.stringify({ ok: false, error: 'sin feed' })`,
      `const entries = []`,
      `{ const re = /<entry>([\\s\\S]*?)<\\/entry>/g; let m; while ((m = re.exec(xml))) { const b = m[1]; const title = (b.match(/<title>([\\s\\S]*?)<\\/title>/) || [])[1] || ''; const link = (b.match(/<link rel="alternate" href="([^"]+)"/) || [])[1] || ''; const pub = (b.match(/<published>([\\s\\S]*?)<\\/published>/) || [])[1] || ''; if (link) entries.push({ title: title.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>'), url: link, published: pub }) } }`,
      `const minScore = Math.max(1, Math.ceil(tokens.length / 2))`,
      `let cand = entries.filter((e) => { const t = e.title.toLowerCase(); return tokens.reduce((n, k) => n + (t.includes(k) ? 1 : 0), 0) >= minScore })`,
      `if (!cand.length) cand = entries.slice()`,
      `cand.sort((a, b) => (a.published < b.published ? 1 : -1))`,
      `const pick = cand[0]`,
      `if (!pick) return JSON.stringify({ ok: false, error: 'sin coincidencias' })`,
      `await page.goto(pick.url, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForSelector(sel.player, { timeout: 20000 })`,
      `const state = await (async () => { for (let i = 0; i < 8; i += 1) { const s = await page.evaluate(() => { const v = document.querySelector('video'); if (!v) return { playing: false, currentTime: 0 }; if (v.paused) { const b = document.querySelector('.ytp-large-play-button, .ytp-play-button'); if (b) b.click() } return { playing: !v.paused, currentTime: v.currentTime } }); if (s.playing) return s; await page.waitForTimeout(700) } return { playing: false, currentTime: 0 } })()`,
      `return JSON.stringify({ ok: true, channel: ${JSON.stringify(channel)}, query: ${JSON.stringify(query)}, candidates: cand.length, title: pick.title, url: pick.url, published: pick.published, playing: state.playing, currentTime: state.currentTime })`,
    ].join('\n')
  },

  latestPostsX({ selectors, args }) {
    const limit = Number(args.limit || 6)
    const sel = JSON.stringify(selectors.x.selectors)
    return [
      `const sel = ${sel}`,
      `await page.goto('https://x.com/home', { waitUntil: 'domcontentloaded' })`,
      `await page.waitForFunction((s) => document.querySelectorAll(s.tweet).length >= 1, sel, { timeout: 25000 })`,
      `const posts = await page.evaluate((s, n) => Array.from(document.querySelectorAll(s.tweet)).slice(0, n).map((t) => { const u = t.querySelector(s.userName); const x = t.querySelector(s.tweetText); return { user: u ? u.textContent.replace(/\\s+/g, ' ').trim() : '', text: x ? x.textContent.replace(/\\s+/g, ' ').trim() : '' } }), sel, ${limit})`,
      `return JSON.stringify({ ok: true, count: posts.length, posts })`,
    ].join('\n')
  },

  wikiSummary({ args }) {
    const wiki = args.page
    if (!wiki) throw new Error('falta --page')
    const url = `https://es.wikipedia.org/wiki/${encodeURIComponent(wiki)}`
    return [
      `await page.goto(${JSON.stringify(url)}, { waitUntil: 'domcontentloaded' })`,
      `await page.waitForSelector('#mw-content-text p', { timeout: 20000 })`,
      `const title = await page.title()`,
      `const intro = await page.evaluate(() => { const ps = Array.from(document.querySelectorAll('#mw-content-text p')); const p = ps.find((e) => (e.textContent || '').trim().length > 40); return p ? p.textContent.replace(/\\s+/g, ' ').trim() : '' })`,
      `const sections = await page.evaluate(() => Array.from(document.querySelectorAll('h2')).map((h) => h.textContent.replace(/\\[.*?\\]/, '').trim()).filter(Boolean).slice(0, 8))`,
      `return JSON.stringify({ ok: true, title, intro: intro.slice(0, 400), sections })`,
    ].join('\n')
  },
}
