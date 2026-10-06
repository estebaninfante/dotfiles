import { execFile } from 'node:child_process'
import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { scenarios, getScenario } from './scenarios.mjs'
import { listAvailable } from './adapters/index.mjs'
import { startServer } from './server.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const RESULTS = join(HERE, 'results.json')

function parseArgs(argv) {
  const out = { adapter: null, scenario: null, json: false, quiet: false, results: null, repeat: 1 }
  for (let i = 2; i < argv.length; i += 1) {
    const a = argv[i]
    if (a === '--adapter') out.adapter = argv[++i]
    else if (a === '--scenario') out.scenario = argv[++i]
    else if (a === '--json') out.json = true
    else if (a === '--quiet') out.quiet = true
    else if (a === '--results') out.results = argv[++i]
    else if (a === '--repeat') out.repeat = Math.max(1, Number(argv[++i]) || 1)
  }
  return out
}

function execJson(bin, args, opts) {
  return new Promise((resolve) => {
    const start = performance.now()
    execFile(
      bin,
      args,
      { timeout: opts.timeoutMs ?? 90000, maxBuffer: 32 * 1024 * 1024, env: opts.env },
      (err, stdout, stderr) => {
        resolve({
          stdout: stdout ?? '',
          stderr: stderr ?? '',
          code: err ? (err.code ?? 1) : 0,
          ms: Math.round(performance.now() - start),
        })
      },
    )
  })
}

async function runOne(adapter, scenario, args) {
  const t0 = performance.now()
  const state = { roundtrips: 0, snapshotChars: 0, tFirst: null }
  const ctx = {
    auth: args.auth ?? null,
    exec: async (bin, cmdArgs, opts = {}) => {
      state.roundtrips += 1
      return execJson(bin, cmdArgs, { ...opts, env: opts.env ?? process.env })
    },
    note: (text) => {
      if (text) state.snapshotChars += text.length
    },
    useful: () => {
      if (state.tFirst === null) state.tFirst = Math.round(performance.now() - t0)
    },
  }

  let result
  let error = null
  try {
    result = await adapter.runScenario(scenario, ctx)
  } catch (e) {
    error = e?.message ?? String(e)
    result = { success: false, detail: `excepcion: ${error}` }
  }
  const total = Math.round(performance.now() - t0)
  return {
    backend: adapter.name,
    scenario: scenario.id,
    success: Boolean(result?.success),
    t_first_useful_ms: state.tFirst,
    total_ms: total,
    roundtrips: state.roundtrips,
    snapshot_chars: state.snapshotChars,
    est_tokens: Math.ceil(state.snapshotChars / 4),
    detail: result?.detail ?? '',
    data: result?.data ?? null,
    error,
    ts: new Date().toISOString(),
  }
}

function fmt(rows) {
  const headers = ['backend', 'scenario', 'ok', 't_first_ms', 'total_ms', 'rt', 'chars', 'tok']
  const body = rows.map((r) => [
    r.backend,
    r.scenario,
    r.success ? 'PASS' : 'FAIL',
    r.t_first_useful_ms ?? '-',
    r.total_ms,
    r.roundtrips,
    r.snapshot_chars,
    r.est_tokens,
  ])
  const widths = headers.map((h, i) =>
    Math.max(h.length, ...body.map((b) => String(b[i]).length)),
  )
  const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join('  ')
  return [line(headers), line(widths.map((w) => '-'.repeat(w))), ...body.map(line)].join('\n')
}

function appendResults(rows, path = RESULTS) {
  mkdirSync(dirname(path), { recursive: true })
  let hist = []
  if (existsSync(path)) {
    try {
      hist = JSON.parse(readFileSync(path, 'utf8'))
    } catch {
      hist = []
    }
  }
  writeFileSync(path, JSON.stringify([...hist, ...rows], null, 2))
}

async function cleanupSessions() {
  await new Promise((resolve) => {
    execFile('agent-browser', ['close', '--all'], { timeout: 15000 }, () => resolve())
  })
  await new Promise((r) => setTimeout(r, 1500))
}

async function main() {
  const args = parseArgs(process.argv)
  await cleanupSessions()
  const srv = await startServer()
  args.auth = { port: srv.port, secret: srv.secret, base: srv.base }
  const avail = await listAvailable()
  const chosen = avail.filter((x) => (args.adapter ? x.adapter.name === args.adapter : true))

  for (const x of chosen) {
    if (!x.available) {
      if (!args.quiet) console.log(`[skip] ${x.adapter.name}: no disponible`)
      continue
    }
    const scen = args.scenario ? [getScenario(args.scenario)].filter(Boolean) : scenarios
    for (const s of scen) {
      for (let i = 0; i < args.repeat; i += 1) {
        if (!args.quiet) console.log(`[run] ${x.adapter.name} / ${s.id}${args.repeat > 1 ? ` (${i + 1}/${args.repeat})` : ''}`)
        const row = await runOne(x.adapter, s, args)
        x.rows = x.rows ?? []
        x.rows.push(row)
      }
    }
  }

  const rows = chosen.flatMap((x) => x.rows ?? [])
  if (!rows.length) {
    console.log('Sin adapters disponibles para correr.')
    return
  }
  const outPath = args.results ? join(process.cwd(), args.results) : RESULTS
  appendResults(rows, outPath)
  if (args.json) console.log(JSON.stringify(rows, null, 2))
  else {
    console.log('')
    console.log(fmt(rows))
    console.log('')
    console.log(`resultados -> ${outPath}`)
    console.log('Actualizar RANKING.md con estos numeros.')
  }
  await srv.close()
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
