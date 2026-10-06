import { readFileSync, appendFileSync, existsSync } from 'node:fs'

export function appendRun(path, row) {
  appendFileSync(path, JSON.stringify(row) + '\n')
}

export function loadRuns(path) {
  if (!existsSync(path)) return []
  return readFileSync(path, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line))
}

export function summarize(path) {
  const rows = loadRuns(path)
  const byTask = new Map()
  for (const row of rows) {
    const entry = byTask.get(row.task) ?? { task: row.task, tries: 0, ok: 0, ms: 0 }
    entry.tries += 1
    if (row.ok) entry.ok += 1
    entry.ms += row.ms || 0
    byTask.set(row.task, entry)
  }
  return Array.from(byTask.values()).map((e) => ({
    task: e.task,
    tries: e.tries,
    okRate: Number((e.ok / e.tries).toFixed(2)),
    avgMs: Math.round(e.ms / e.tries),
  }))
}
