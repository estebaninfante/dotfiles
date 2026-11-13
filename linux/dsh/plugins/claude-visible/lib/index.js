/**
 * dsh-local-claude-visible — comandos del harness para ver (y lanzar) delegaciones a
 * Claude Code, y para listar todas las skills instaladas sin salir del chat:
 *
 *   /claude               lista las delegaciones (estado + última línea)
 *   /claude status [n]    detalle de una (corriendo o terminada, últimas líneas)
 *   /claude read [n]      salida completa de una delegación
 *   /claude start <brief> lanza una delegación (usa el helper delegar-claude)
 *   /skills               todas las skills instaladas, con su descripción
 *   /skills <name>        ruta del SKILL.md y descripción de una skill
 *
 * Todo el estado vive en ~/.local/state/delegar-claude/<nombre>/, que es lo que
 * escribe el helper `delegar-claude` (brief.md, out.log, pid).
 */
import { execFile } from 'node:child_process'
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { promisify } from 'node:util'

const execFileAsync = promisify(execFile)

// Sin imports del harness a propósito: el brand de `definitionId` es la identidad
// (`id => id`), así que el plugin queda sin dependencias y se puede probar con node
// suelto. Menos superficie para que un cambio de versión lo rompa.
const CommandDefinitionId = (id) => id

const STATE_DIR = join(homedir(), '.local', 'state', 'delegar-claude')
const SKILLS_DIR = join(homedir(), '.agents', 'skills')
const MAX_READ = 6000

/** ¿El pid del archivo sigue vivo? */
function isRunning(dir) {
  try {
    const pid = Number.parseInt(readFileSync(join(dir, 'pid'), 'utf8').trim(), 10)
    if (!Number.isInteger(pid) || pid <= 0) return false
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

/** Sesiones de delegación, la más nueva primero. */
function listSessions() {
  if (!existsSync(STATE_DIR)) return []
  return readdirSync(STATE_DIR)
    .map((name) => join(STATE_DIR, name))
    .filter((dir) => {
      try {
        return statSync(dir).isDirectory()
      } catch {
        return false
      }
    })
    .sort((a, b) => {
      try {
        return statSync(join(b, 'brief.md')).mtimeMs - statSync(join(a, 'brief.md')).mtimeMs
      } catch {
        return 0
      }
    })
}

function lastLine(dir, n = 1) {
  try {
    const lines = readFileSync(join(dir, 'out.log'), 'utf8').trimEnd().split('\n')
    return lines.slice(-n).join('\n').trim()
  } catch {
    return ''
  }
}

function pickSession(raw) {
  const wanted = (raw ?? '').trim()
  const all = listSessions()
  if (all.length === 0) return undefined
  if (!wanted) return all[0]
  const exact = all.find((dir) => dir.endsWith(`/${wanted}`))
  if (exact) return exact
  const partial = all.find((dir) => dir.includes(`/${wanted}`))
  return partial ?? all[0]
}

/** Primer bloque `---` de un SKILL.md (name/description). */
function readFrontmatter(file) {
  try {
    const text = readFileSync(file, 'utf8')
    const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---/)
    if (!match) return {}
    const meta = {}
    for (const line of match[1].split('\n')) {
      const kv = line.match(/^([a-zA-Z_-]+):\s*(.*)$/)
      if (kv) meta[kv[1]] = kv[2].replace(/^["']|["']$/g, '')
    }
    return meta
  } catch {
    return {}
  }
}

function listSkills() {
  if (!existsSync(SKILLS_DIR)) return []
  return readdirSync(SKILLS_DIR)
    .map((entry) => ({ id: entry, dir: join(SKILLS_DIR, entry) }))
    .map(({ id, dir }) => {
      const file = join(dir, 'SKILL.md')
      if (!existsSync(file)) return undefined
      const meta = readFrontmatter(file)
      return { id, file, name: meta.name || id, description: meta.description || '' }
    })
    .filter(Boolean)
    .sort((a, b) => a.name.localeCompare(b.name))
}

function listDelegationsText() {
  const all = listSessions()
  if (all.length === 0) {
    return 'No hay delegaciones. Lanzá una con `/claude start <brief.md>` o con `delegar-claude start <brief.md>`.'
  }
  const rows = all.map((dir) => {
    const name = dir.split('/').pop()
    const state = isRunning(dir) ? 'corriendo' : 'terminada'
    const tail = lastLine(dir).replace(/\s+/g, ' ').slice(0, 90)
    return `${name.padEnd(22)} ${state.padEnd(10)} ${tail}`
  })
  return ['Delegaciones a Claude (`~/.local/state/delegar-claude/`):', ...rows].join('\n')
}

async function handleClaude(invocation) {
  const raw = (invocation?.rawInput ?? '').trim()
  const [sub, ...rest] = raw.split(/\s+/)
  const arg = rest.join(' ').trim()

  if (!sub || sub === 'list') return { kind: 'success', text: listDelegationsText() }

  if (sub === 'status') {
    const dir = pickSession(arg)
    if (!dir) return { kind: 'error', text: 'No hay delegaciones para mirar.' }
    const name = dir.split('/').pop()
    const state = isRunning(dir) ? 'corriendo' : 'terminada'
    return {
      kind: 'success',
      text: [`sesion: ${name}`, `estado: ${state}`, `log: ${join(dir, 'out.log')}`, '', '--- últimas líneas ---', lastLine(dir, 15) || '(sin salida todavía)'].join(
        '\n',
      ),
    }
  }

  if (sub === 'read') {
    const dir = pickSession(arg)
    if (!dir) return { kind: 'error', text: 'No hay delegaciones para leer.' }
    let text = ''
    try {
      text = readFileSync(join(dir, 'out.log'), 'utf8')
    } catch {
      return { kind: 'error', text: `No pude leer ${join(dir, 'out.log')}` }
    }
    if (text.length === 0) text = '(sin salida todavía)'
    if (text.length > MAX_READ) text = `…(recortado)\n${text.slice(-MAX_READ)}`
    return { kind: 'success', text }
  }

  if (sub === 'start') {
    if (!arg) return { kind: 'error', text: 'Uso: /claude start <ruta-al-brief.md>' }
    try {
      const { stdout, stderr } = await execFileAsync('delegar-claude', ['start', arg, '--name', `web-${Date.now()}`], { timeout: 20000 })
      return { kind: 'success', text: (stdout || stderr || 'delegación lanzada').trim() }
    } catch (error) {
      return { kind: 'error', text: `No pude lanzar la delegación: ${error?.stderr || error?.message || error}` }
    }
  }

  return { kind: 'error', text: 'Uso: /claude [list|status [n]|read [n]|start <brief.md>]' }
}

function handleSkills(invocation) {
  const raw = (invocation?.rawInput ?? '').trim()
  const skills = listSkills()
  if (skills.length === 0) return { kind: 'error', text: `No encontré skills en ${SKILLS_DIR}` }

  if (!raw) {
    const rows = skills.map((skill) => {
      const desc = skill.description.replace(/\s+/g, ' ').slice(0, 110)
      return `${skill.name.padEnd(28)} ${desc}`
    })
    return { kind: 'success', text: [`Skills instaladas (${skills.length}) en ${SKILLS_DIR}:`, ...rows, '', 'Detalle: /skills <nombre>'].join('\n') }
  }

  const found = skills.find((skill) => skill.name === raw || skill.id === raw)
  if (!found) {
    const near = skills.filter((skill) => skill.name.includes(raw) || skill.id.includes(raw)).map((skill) => skill.name)
    return { kind: 'error', text: near.length ? `No hay "${raw}". Parecidas: ${near.join(', ')}` : `No hay una skill "${raw}".` }
  }
  return { kind: 'success', text: [`skill: ${found.name}`, `id: ${found.id}`, `archivo: ${found.file}`, '', found.description].join('\n') }
}

/** Envuelve un handler para que un error nunca tumbe el plugin ni el comando. */
function safe(handler) {
  return async (invocation) => {
    try {
      return await handler(invocation)
    } catch (error) {
      return { kind: 'error', text: `Error en el comando: ${error?.message || error}` }
    }
  }
}

export const name = 'local-claude-visible'

export const inject = ['commands']


export function apply(ctx) {
  ctx.commands.register({
    definitionId: CommandDefinitionId('dsh-local-claude-visible/skills'),
    name: 'skills',
    description: 'Listar las skills instaladas y ver una en detalle',
    input: { hint: '[<nombre>]' },
    handler: safe(handleSkills),
  })
}
