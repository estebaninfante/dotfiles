import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { capabilities, weights } from './capabilities.mjs'
import { scenarios } from './scenarios.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const argFile = process.argv[2] ? resolve(process.cwd(), process.argv[2]) : null
const RESULTS = join(HERE, 'results.json')
const TMP = join(HERE, 'tmp')
const OUT = join(HERE, '..', 'SCORES.md')

function loadRows() {
  const files = argFile ? [argFile] : [RESULTS]
  if (!argFile && existsSync(TMP)) {
    for (const f of readdirSync(TMP)) {
      if (f.endsWith('.json') && f !== 'tools.json') files.push(join(TMP, f))
    }
  }
  const rows = []
  for (const file of files) {
    if (!existsSync(file)) continue
    let parsed = []
    try {
      parsed = JSON.parse(readFileSync(file, 'utf8'))
    } catch {
      continue
    }
    for (const r of parsed) if (r?.backend && r?.scenario) rows.push(r)
  }
  return rows
}

function minMax(values) {
  return { min: Math.min(...values), max: Math.max(...values) }
}

function scaled(value, { min, max }) {
  if (max === min) return 8
  return 10 - 9 * ((value - min) / (max - min))
}

function avg(nums) {
  return nums.reduce((a, b) => a + b, 0) / nums.length
}

function round1(n) {
  return Math.round(n * 10) / 10
}

function clamp(n, lo, hi) {
  return Math.min(hi, Math.max(lo, n))
}

function tokenScore(tokens) {
  return clamp(10 - 2.5 * Math.log10(Math.max(tokens, 10) / 10), 0, 10)
}

const rows = loadRows()
const bestEffortIds = new Set(scenarios.filter((s) => s.bestEffort).map((s) => s.id))
const backends = {}
const bestEffort = {}
for (const r of rows) {
  const b = (backends[r.backend] ??= {
    tokens: [],
    speed: [],
    rt: [],
    attempts: 0,
    pass: 0,
    authPass: 0,
    authAttempts: 0,
  })
  b.attempts += 1
  if (r.success) b.pass += 1
  b.tokens.push(r.est_tokens ?? 0)
  b.speed.push(r.t_first_useful_ms ?? r.total_ms ?? 90000)
  b.rt.push(r.roundtrips ?? 0)
  if (r.scenario === 'auth_roundtrip') {
    b.authAttempts += 1
    if (r.success) b.authPass += 1
  }
  if (bestEffortIds.has(r.scenario)) {
    const e = (bestEffort[r.backend] ??= { attempts: 0, pass: 0 })
    e.attempts += 1
    if (r.success) e.pass += 1
  }
}
const weightSum = Object.values(weights).reduce((a, b) => a + b, 0)

const names = Object.keys(backends)
if (!names.length) {
  console.log('Sin filas para scorear.')
  process.exit(1)
}
const speedStat = minMax(names.map((n) => avg(backends[n].speed)))
const rtStat = minMax(names.map((n) => avg(backends[n].rt)))

const scored = names.map((n) => {
  const b = backends[n]
  const cap = capabilities[n] ?? { realProfile: false, goal: 5, ext: 5, maint: 5, note: '' }
  const authRate = b.authAttempts ? b.authPass / b.authAttempts : cap.realProfile ? 1 : 0.4
  const parts = {
    tokens: tokenScore(avg(b.tokens)),
    speed: scaled(avg(b.speed), speedStat),
    roundtrips: b.rt.some((x) => x > 0) ? scaled(avg(b.rt), rtStat) : 6,
    realProfile: round1(10 * authRate),
    goal: cap.goal,
    ext: cap.ext,
    maint: cap.maint,
  }
  const reliability = b.pass / b.attempts
  const raw = Object.entries(weights).reduce((sum, [k, w]) => sum + w * parts[k], 0) / weightSum
  return {
    backend: n,
    total: round1(raw * reliability),
    raw: round1(raw),
    parts,
    reliability,
    attempts: b.attempts,
    avgTokens: Math.round(avg(b.tokens)),
    avgSpeed: Math.round(avg(b.speed)),
    avgRt: round1(avg(b.rt)),
    note: cap.note,
  }
})

scored.sort((a, b) => b.total - a.total)

const lines = []
lines.push('# SCORES — browser-agent backends')
lines.push('')
lines.push(`Generado por bench/score.mjs. Pesos: ${Object.entries(weights).map(([k, w]) => `${k}=${w}`).join(', ')}.`)
lines.push('tokens = escala log absoluta = costo-a-goal (autoría del programa + payload leído). total = raw * fiabilidad(pass/intentos).')
lines.push('Fiabilidad = solo escenarios controlables; los marcados bestEffort (red externa, p.ej. YouTube anti-bot) se reportan aparte.')
lines.push('')
lines.push('| Backend | TOTAL | raw | fiabilidad | intentos | tokens | speed | rt | realProf | goal | ext | maint |')
lines.push('|---|---|---|---|---|---|---|---|---|---|---|---|')
for (const s of scored) {
  lines.push(
    `| ${s.backend} | **${s.total}** | ${s.raw} | ${s.reliability.toFixed(2)} | ${s.attempts} | ${round1(s.parts.tokens)} | ${round1(s.parts.speed)} | ${round1(s.parts.roundtrips)} | ${s.parts.realProfile} | ${s.parts.goal} | ${s.parts.ext} | ${s.parts.maint} |`,
  )
}
lines.push('')
lines.push('## Detalle medido')
lines.push('')
lines.push('| Backend | avg_tokens | avg_t_first_ms | avg_roundtrips |')
lines.push('|---|---|---|---|')
for (const s of scored) lines.push(`| ${s.backend} | ${s.avgTokens} | ${s.avgSpeed} | ${s.avgRt} |`)
lines.push('')
lines.push('## Capacidades')
lines.push('')
for (const s of scored) lines.push(`- **${s.backend}**: ${s.note}`)
lines.push('')
lines.push('## Best-effort (red externa, fuera de fiabilidad)')
lines.push('')
lines.push('| Backend | bestEffort_pass/intentos | rate |')
lines.push('|---|---|---|')
for (const n of names) {
  const e = bestEffort[n]
  if (!e) continue
  lines.push(`| ${n} | ${e.pass}/${e.attempts} | ${(e.pass / e.attempts).toFixed(2)} |`)
}
lines.push('')
writeFileSync(OUT, lines.join('\n'))

console.log(lines.join('\n'))
console.log(`\nSCORES -> ${OUT}`)
console.log(`WINNER: ${scored[0].backend} = ${scored[0].total} (raw ${scored[0].raw}, fiabilidad ${scored[0].reliability.toFixed(2)})`)
