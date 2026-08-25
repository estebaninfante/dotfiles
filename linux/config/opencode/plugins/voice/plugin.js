// voice — opencode plugin: voz local para eventos de la sesion.
//
// Integra opencode con el sistema de voz local (linux/voice + ~/.local/bin/voice).
//
// 1. Voz (TTS) para:
//    - session.idle  → resumen breve de la respuesta (o texto completo si
//                       state.json → tts.mode == "full")
//    - permiso       → anuncia el comando que opencode quiere ejecutar
//    - session.error → anuncia el error sin leer el stack trace
//    - tool activity → (opcional, throttled) "opencode esta ejecutando <tool>"
// 2. Entrada (STT → opencode): vigila ~/.cache/voice/to-opencode.json. Cuando
//    `voice listen` transcribe una frase, este plugin la inyecta en la sesion
//    activa via client.session.prompt. LA VOZ NO BYPASSEA PERMISOS: la frase
//    entra como un prompt mas del usuario y pasa por el flujo de permisos
//    normal de opencode.
//
// TTS habla via `~/.local/bin/voice speak <texto>` (cola del daemon si
// voice-daemon.service esta activo; si no, sintesis directa en background).
// El push a ntfy.sh sigue viviendo en plugins/notify-sound (visual separado).
//
// Runtime config: lee tts.enabled / tts.mode desde
// ~/.local/state/voice/state.json (overrides por-maquina de config.toml).

import fs, os from 'fs';

const HOME = process.env.HOME;
const VOICE = `${HOME}/.local/bin/voice`;
const CACHE = process.env.VOICE_CACHE_DIR || `${HOME}/.cache/voice`;
const OC_FILE = `${CACHE}/to-opencode.json`;
const LOG_FILE = process.env.VOICE_LOG || `${CACHE}/opencode-voice.log`;
const LOCK_DIR = '/tmp/opencode/voice-locks';
const LOCK_TTL_MS = 60000;

// state.json overrides (tts.enabled, tts.mode, ...)
function readState() {
  try {
    return JSON.parse(fs.readFileSync(`${HOME}/.local/state/voice/state.json`, 'utf8'))?.tts || {};
  } catch { return {}; }
}

function ttsEnabled(state = readState()) {
  return state.enabled !== false;
}

function dbg(msg) {
  try { fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`); } catch {}
}

function acquireLock(key) {
  try {
    const dir = `${LOCK_DIR}/${key}`;
    try { fs.mkdirSync(dir); } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const age = Date.now() - fs.statSync(dir).mtimeMs;
      if (age > LOCK_TTL_MS) {
        fs.rmSync(dir, { recursive: true, force: true });
        fs.mkdirSync(dir);
      } else return false;
    }
    fs.writeFileSync(`${dir}/pid`, String(process.pid));
    return () => { try { fs.writeFileSync(`${dir}/ts`, String(Date.now())); } catch {} };
  } catch { return () => {}; }
}

function speak(text, key) {
  if (!text || !key) return;
  if (!ttsEnabled()) { dbg(`tts off, skip: ${key}`); return; }
  const release = acquireLock(key);
  if (release === false) return;
  try {
    Bun.spawn([VOICE, 'speak', text], { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg(`speak[${key}]: ${text.slice(0, 200)}`);
  } catch (e) { dbg(`speak ERR: ${e.message}`); } finally { release(); }
}

// sleepy/session util ─────────────────────────────────────────────────────
function sessionIdOf(e) {
  return e.properties?.sessionID || e.properties?.id || e.sessionID || e.id || '';
}

function isSessionIdle(e) {
  if (e.type === 'session.idle') return true;
  if (e.type === 'session.status')
    return e.properties?.status?.type === 'idle' || e.status?.type === 'idle';
  return false;
}

function isPermissionAsked(e) {
  return e.type === 'permission.asked' || e.type === 'permission.updated';
}

function permissionDetail(e) {
  try {
    const p = e.permission || e.properties || {};
    return p.request?.command || p.request?.tool || p.prompt
      || (p.pattern ? String(p.pattern) : '') || p.title || '';
  } catch { return ''; }
}

// Extrae el texto de un mensaje assistant sumando los parts de texto.
function assistantText(msg) {
  if (!msg?.parts) return '';
  const out = [];
  for (const p of msg.parts) {
    if (p.type === 'text' && typeof p.text === 'string') out.push(p.text);
    if (p.type === 'texts') out.push(String(p.texts).trim());
  }
  return out.join('\n').trim();
}

// Resumen hablado: texto del ultimo mensaje assistant, recortado.
// mode=full → se lee completo (cap ~4000 chars); summary → ~320 chars.
function summarize(raw, mode) {
  if (!raw) return '';
  const flat = raw.replace(/\s+/g, ' ').trim();
  const cap = mode === 'full' ? 4000 : 320;
  if (flat.length <= cap) return flat;
  const cut = flat.slice(0, cap);
  const lastSentence = cut.lastIndexOf('.');
  const end = lastSentence > cap / 2 ? lastSentence + 1 : cap;
  return flat.slice(0, end) + ' (respuesta recortada)';
}

// tool activity: solo anuncia cuando el tool lleva rato corriendo y
// throttled (una vez por tool por ~30s).
const toolShout = {};
function toolAnnounce(e) {
  try {
    const part = e.properties || {};
    if (part.type !== 'tool') return;
    const tool = part.tool || part.state?.tool || '';
    const args = part.state?.input?.command || part.args || part.call?.input || '';
    const name = tool || String(args).split(/\s+/)[0] || 'herramienta';
    const now = Date.now();
    if (now - (toolShout[name] || 0) < 30000) return;
    toolShout[name] = now;
    speak(`Opencode esta ejecutando: ${name}`, `tool-${name}`);
  } catch {}
}

// ── sesion activa trackeada ─────────────────────────────────────────────
let lastSessionId = '';

async function summaryForSession(client, sid, mode) {
  try {
    const res = await client.session.messages({ path: { id: sid } });
    const msgs = res?.data || [];
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === 'assistant') {
        const text = assistantText(msgs[i]);
        if (text) return summarize(text, mode);
      }
    }
  } catch (e) { dbg(`summary ERR: ${e.message}`); }
  return '';
}

async function onIdle(client, sid) {
  const mode = readState().mode || 'summary';
  const summary = await summaryForSession(client, sid, mode);
  if (!summary) {
    speak('Opencode: la sesion termino', `idle-${sid || 'default'}`);
    return;
  }
  speak(`Termine. ${summary}`, `idle-${sid || 'default'}`);
}

// ── entrada voz → opencode: to-opencode.json ────────────────────────────
let lastTs = 0;
let watchT = null;

async function consumeVoiceInjection(client) {
  if (!fs.existsSync(OC_FILE)) return;
  let entry;
  try { entry = JSON.parse(fs.readFileSync(OC_FILE, 'utf8')); } catch { return; }
  const text = entry?.text;
  if (!text || (entry.ts || 0) <= lastTs) return;
  lastTs = entry.ts;
  // elimina el archivo (un solo consumidor gana; los demas ven ENOENT)
  try { fs.unlinkSync(OC_FILE); } catch {}
  const sid = entry.sessionID || lastSessionId;
  if (!sid) { dbg('voice injection: sin sesion activa (escuchando en otra?)'); return; }
  const state = readState();
  try {
    await client.session.prompt({ path: { id: sid }, body: { text } });
    dbg(`voice injection → session ${sid}: ${text.slice(0, 120)}`);
    if (state.enabled !== false) speak('Recibido.', `inject-${sid}`);
  } catch (e) { dbg(`prompt ERR: ${e.message}`); }
}

function armWatcher(client) {
  try {
    fs.watch(CACHE, { persistent: false }, (_evt, filename) => {
      if (filename !== 'to-opencode.json') return;
      if (watchT) clearTimeout(watchT);
      watchT = setTimeout(() => consumeVoiceInjection(client), 250);
    });
  } catch (e) { dbg(`watch ERR: ${e.message}`); }
}

export default async ({ $, client }) => {
  dbg('plugin init (voice)');
  armWatcher(client);
  return {
    event: async ({ event }) => {
      try {
        const sid = sessionIdOf(event);
        if (sid) lastSessionId = sid;

        if (isSessionIdle(event)) {
          dbg('→ idle');
          await onIdle(client, sid);
        } else if (isPermissionAsked(event)) {
          const detail = permissionDetail(event);
          speak(`Opencode necesita permiso para: ${detail || 'ejecutar'}`, `perm-${sid || 'default'}`);
        } else if (event.type === 'session.error') {
          const msg = String(event.properties?.error?.message || event.error || '')
            .replace(/\s+/g, ' ').trim().slice(0, 160);
          speak(`Opencode encontro un error.${msg ? ` ${msg}` : ''}`, `err-${sid || 'default'}`);
        } else if (event.type === 'message.part.updated') {
          toolAnnounce(event);
        }
      } catch (e) { dbg(`handler ERR: ${e.message}`); }
    },
  };
};