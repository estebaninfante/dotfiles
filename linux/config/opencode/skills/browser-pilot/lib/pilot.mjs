import { execFile } from 'node:child_process'
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { promisify } from 'node:util'
import { tasks } from './tasks.mjs'
import { appendRun, summarize } from './runlog.mjs'

const exec = promisify(execFile)
const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..')
const RUNS = join(ROOT, 'runs.jsonl')
const TMP = '/tmp/opencode'

function parseArgs(argv) {
  const out = { _: [], flags: {} }
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i]
    if (token.startsWith('--')) {
      const key = token.slice(2)
      const next = argv[i + 1]
      if (next && !next.startsWith('--')) {
        out.flags[key] = next
        i += 1
      } else {
        out.flags[key] = 'true'
      }
    } else {
      out._.push(token)
    }
  }
  return out
}

function buildCode(taskName, args) {
  const selectors = JSON.parse(readFileSync(join(ROOT, 'selectors.json'), 'utf8'))
  const task = tasks[taskName]
  if (!task) throw new Error(`tarea desconocida: ${taskName}. Disponibles: ${Object.keys(tasks).join(', ')}`)
  return task({ selectors, args })
}

async function runTask(taskName, args, session) {
  const code = buildCode(taskName, args)
  const file = join(TMP, `pilot-${taskName}-${Date.now()}.js`)
  writeFileSync(file, code)
  const started = Date.now()
  const { stdout } = await exec(
    'browser-control',
    ['execute', '--session', session, '--file', file, '--json'],
    { maxBuffer: 64 * 1024 * 1024, timeout: 120000 },
  )
  const ms = Date.now() - started
  const envelope = JSON.parse(stdout)
  const parsed = envelope.text ? JSON.parse(envelope.text) : null
  return { ms, envelope, parsed, file }
}

async function main() {
  const { _, flags } = parseArgs(process.argv.slice(2))
  if (_.length === 0 || flags.help === 'true') {
    console.log('uso: node pilot.mjs <tarea> --session <id> [--channel X | --query Y | --page Z] [--stats] [--json]')
    console.log('tareas:', Object.keys(tasks).join(', '))
    process.exit(0)
  }
  if (flags.stats === 'true') {
    console.log(JSON.stringify(summarize(RUNS), null, 2))
    process.exit(0)
  }

  const taskName = _[0]
  const session = flags.session || process.env.PILOT_SESSION
  if (!session) {
    console.error('falta --session <id> (o env PILOT_SESSION)')
    process.exit(2)
  }
  const args = { ...flags }
  delete args.session
  delete args.json
  delete args.stats

  let outcome
  try {
    outcome = await runTask(taskName, args, session)
  } catch (error) {
    const row = { ts: new Date().toISOString(), task: taskName, session, ok: false, ms: 0, error: String(error.message || error) }
    appendRun(RUNS, row)
    console.error(JSON.stringify(row))
    process.exit(1)
  }

  const ok = Boolean(outcome.parsed && outcome.parsed.ok !== false)
  const row = { ts: new Date().toISOString(), task: taskName, session, ok, ms: outcome.ms, result: outcome.parsed }
  appendRun(RUNS, row)

  if (flags.json === 'true') {
    console.log(JSON.stringify(row))
  } else {
    console.log(`[${ok ? 'OK' : 'FAIL'}] ${taskName} en ${outcome.ms}ms`)
    console.log(JSON.stringify(outcome.parsed, null, 2))
  }
  process.exit(ok ? 0 : 1)
}

main()
