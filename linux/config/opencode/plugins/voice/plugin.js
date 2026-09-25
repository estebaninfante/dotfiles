// voice — opencode plugin v4 (event-driven + custom tool, sin timers)
//
// opencode NO ejecuta setInterval/setTimeout en plugins → TODO es reactivo.
// Los archivos se escriben sincronos dentro de los handlers.
//
// Idea central: el AGENTE escribe el contenido (tiene el contexto completo).
// El plugin solo lo entrega: notificacion de escritorio + push ntfy + VOZ
// (Chatterbox) para TODAS las notificaciones.
//
// Modo ON/OFF (default OFF): controla SOLO las notificaciones del agente.
//   - Comando /notify on|off  →  ~/.local/bin/voice notify <on|off>
//   - Estado en ~/.local/state/opencode/voice-notify ('1'/'0')
//   - OFF: la tool notify_user NO envia nada.
//   - ON:  notify_user envia (escritorio + push + voz).
//
// Permisos y errores: SIEMPRE avisan (importantes), sin importar el toggle.
//
//  1. Tool `notify_user`: args message (obligatorio), title?, priority? (1-5).
//  2. permission.asked  → notificacion + push + voz (siempre).
//  3. session.error     → notificacion + push + voz (siempre).
//
// TTS (voz): respetado SIEMPRE. Toggle `voice tts on|off` (state.json +
// config.toml). OFF → no se spawnea `voice speak` (0 forks, cero motores).
// Extra: si engine_<lang> = chatterbox, la voz se salta (nunca cargarlo).

import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'fs';
import { tool } from '@opencode-ai/plugin';

const DEBUG_LOG = process.env.VOICE_PLUGIN_LOG || '/tmp/opencode/voice-plugin.log';
const CACHE_DIR = `${process.env.HOME}/.cache/voice`;
const LAST_MESSAGE_FILE = `${CACHE_DIR}/last-message.txt`;
const NOTIFY_FILE = `${process.env.HOME}/.local/state/opencode/voice-notify`;
const VOICE_BIN = `${process.env.HOME}/.local/bin/voice`;

const TOPIC = (() => {
  try {
    const m = readFileSync(`${process.env.HOME}/.config/machine-type`, 'utf8').trim();
    return m === 'desktop' ? 'opencode-desktop' : 'opencode-laptop';
  } catch { return 'opencode-laptop'; }
})();

function dbg(msg) {
  try {
    mkdirSync(DEBUG_LOG.substring(0, DEBUG_LOG.lastIndexOf('/')), { recursive: true });
    appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] [pid ${process.pid}] ${msg}\n`);
  } catch {}
}

function notifyEnabled() {
  try { return readFileSync(NOTIFY_FILE, 'utf8').trim() === '1'; }
  catch { return false; } // default OFF
}

// ── TTS: estado efectivo (state.json pisa config.toml) ───────────────────
function parseTomlSection(path, section) {
  const out = {};
  let cur = null;
  for (const raw of readFileSync(path, 'utf8').split('\n')) {
    const line = raw.replace(/#.*$/, '').trim();
    if (!line) continue;
    const hdr = line.match(/^\[(.+)\]$/);
    if (hdr) { cur = hdr[1].trim(); continue; }
    if (cur !== section) continue;
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const k = line.slice(0, eq).trim();
    let v = line.slice(eq + 1).trim();
    if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
    out[k] = v;
  }
  return out;
}

function ttsState() {
  const home = process.env.HOME;
  let cfg = {};
  try { cfg = parseTomlSection(`${home}/.config/voice/config.toml`, 'tts'); } catch {}
  try {
    const s = JSON.parse(readFileSync(`${home}/.local/state/voice/state.json`, 'utf8'));
    if (s?.tts && typeof s.tts === 'object') Object.assign(cfg, s.tts);
  } catch {}
  const enabled = String(cfg.enabled ?? 'true').toLowerCase();
  const lang = String(cfg.lang || 'es');
  const engine = String(cfg[`engine_${lang}`] || cfg.engine || 'piper');
  return {
    enabled: enabled !== 'false' && enabled !== '0',
    engine,
  };
}

// Voz hablada: solo si TTS ON y el motor NO es chatterbox.
function speakAllowed() {
  const t = ttsState();
  if (!t.enabled) { dbg('speak: TTS OFF, se omite'); return false; }
  if (t.engine === 'chatterbox') { dbg('speak: engine=chatterbox, se omite'); return false; }
  return true;
}

function sessionIdOf(event) {
  return event.properties?.sessionID || event.properties?.id
    || event.sessionID || event.id || '';
}

// ── Entrega: escritorio + push + voz (Chatterbox) ───────────────────────
async function deliver(title, body, priority) {
  try {
    mkdirSync(CACHE_DIR, { recursive: true });
    writeFileSync(LAST_MESSAGE_FILE, body);
  } catch (e) { dbg(`writeCache ERROR: ${e.message}`); }

  try {
    Bun.spawn(['notify-send', '-t', '8000', title, body], { stdio: ['ignore', 'ignore', 'ignore'] });
  } catch (e) { dbg(`notify-send ERROR: ${e.message}`); }

  if (speakAllowed()) {
    try {
      Bun.spawn([VOICE_BIN, 'speak', body], { stdio: ['ignore', 'ignore', 'ignore'] });
    } catch (e) { dbg(`voice speak ERROR: ${e.message}`); }
  }

  try {
    const res = await fetch(`https://ntfy.sh/${TOPIC}`, {
      method: 'POST',
      body,
      headers: {
        'Title': title,
        'Priority': String(priority || 3),
        'Tags': priority >= 4 ? 'warning' : 'white_check_mark',
      },
    });
    dbg(`deliver: notify+speak+push ${res.status} | ${title}`);
  } catch (e) { dbg(`deliver push ERROR: ${e.message}`); }
}

const recent = new Map();
function alreadyFired(kind, sid) {
  const key = `${kind}:${sid || 'nosid'}`;
  const now = Date.now();
  if (now - (recent.get(key) || 0) < 15000) return true;
  recent.set(key, now);
  if (recent.size > 64) for (const [k, t] of recent) if (now - t > 60000) recent.delete(k);
  return false;
}

export default async ({ client }) => {
  dbg('plugin init v4 (notify_user + permisos/errores, todo con voz)');
  return {
    tool: {
      notify_user: tool({
        description:
          'Avisa al usuario con notificacion de escritorio, push al celular y (si TTS ON) voz. '
          + 'Usala al terminar una tarea o cuando algo merezca atencion. Redacta el mensaje tu '
          + 'mismo, con contexto, en espanol claro y breve (1-2 frases). '
          + 'Solo se entrega si las notificaciones estan activas (/notify on); si estan OFF, '
          + 'la llamada se ignora.',
        args: {
          message: tool.schema.string().describe('Texto de la notificacion (espanol, breve, con contexto)'),
          title: tool.schema.string().optional().describe('Titulo corto de la notificacion'),
          priority: tool.schema.number().int().min(1).max(5).optional()
            .describe('Prioridad 1-5 (5 = urgente). Default 3'),
        },
        async execute(args) {
          const message = String(args.message || '').trim();
          if (!message) return 'Error: message vacio';
          if (!notifyEnabled()) {
            dbg('notify_user: OFF, ignorado');
            return 'Notificaciones OFF (activa con /notify on). No se envio nada.';
          }
          const title = (args.title || 'opencode').trim();
          await deliver(title, message, args.priority || 3);
          return `Notificado: ${message}`;
        },
      }),
    },

    event: async ({ event }) => {
      try {
        const sid = sessionIdOf(event);

        if (event.type === 'permission.asked' || event.type === 'permission.updated') {
          if (alreadyFired('perm', sid)) return;
          const detail = (() => {
            try {
              const p = event.permission || event.properties || {};
              return p.request?.command || p.request?.tool || p.prompt
                || (p.pattern ? String(p.pattern) : '') || p.title || '';
            } catch { return ''; }
          })();
          await deliver('opencode: permiso', detail || 'Pide permiso', 4);
          return;
        }

        if (event.type === 'session.error') {
          if (alreadyFired('error', sid)) return;
          const errMsg = String(event.properties?.error || event.error || 'Error desconocido').slice(0, 300);
          await deliver('opencode: error', errMsg, 4);
          return;
        }
      } catch (e) {
        dbg(`event handler ERROR: ${e.message}`);
      }
    },
  };
};
