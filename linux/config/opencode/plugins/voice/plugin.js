// voice — opencode plugin v3 (event-driven + custom tool, sin timers)
//
// opencode NO ejecuta setInterval/setTimeout en plugins → TODO es reactivo.
// Los archivos se escriben sincronos dentro de los handlers.
//
// Idea central: el AGENTE escribe el contenido de la notificacion (tiene el
// contexto completo), no un LLM externo. El plugin solo lo entrega.
//
//  1. Tool `notify_user` (el agente la llama al terminar una tarea):
//       args: message (obligatorio), title?, priority? (1-5), speak? (bool)
//       → notify-send + push ntfy + guarda last-message.txt
//       → habla por Chatterbox si speak=true o auto-speak ON
//
//  2. message.updated → guarda la ultima respuesta del asistente en
//       ~/.cache/voice/last-response.txt (fallback on-demand).
//
//  3. permission.asked / session.error → notificacion + push (el agente no
//       puede llamar tool en esos momentos). Habla si auto-speak ON.
//
// On-demand (Hyprland Super+Shift+V → `voice summarize`):
//   Habla ~/.cache/voice/last-message.txt (ultima notificacion del agente)
//   o last-response.txt si aun no hay notificacion.
//
// Toggle auto-speak (Super+Ctrl+V → `voice toggle`):
//   escribe ~/.local/state/opencode/voice-auto-speak ('1'/'0', default '0').
//   El plugin lo lee en cada evento/tool-call.

import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'fs';
import { tool } from '@opencode-ai/plugin';

const DEBUG_LOG = process.env.VOICE_PLUGIN_LOG || '/tmp/opencode/voice-plugin.log';
const CACHE_DIR = `${process.env.HOME}/.cache/voice`;
const LAST_RESPONSE_FILE = `${CACHE_DIR}/last-response.txt`;
const LAST_MESSAGE_FILE = `${CACHE_DIR}/last-message.txt`;
const AUTO_SPEAK_FILE = `${process.env.HOME}/.local/state/opencode/voice-auto-speak`;
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

function writeCache(path, text) {
  try {
    mkdirSync(CACHE_DIR, { recursive: true });
    writeFileSync(path, text);
  } catch (e) { dbg(`writeCache ${path} ERROR: ${e.message}`); }
}

function autoSpeakEnabled() {
  try { return readFileSync(AUTO_SPEAK_FILE, 'utf8').trim() === '1'; }
  catch { return false; } // default OFF
}

// ── Salidas ─────────────────────────────────────────────────────────────
function notifyDesktop(title, body) {
  try {
    Bun.spawn(['notify-send', '-t', '8000', title, body], { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg(`notify: ${title} | ${body}`);
  } catch (e) { dbg(`notify-send ERROR: ${e.message}`); }
}

async function push(title, message, priority) {
  try {
    const res = await fetch(`https://ntfy.sh/${TOPIC}`, {
      method: 'POST',
      body: message,
      headers: {
        'Title': title,
        'Priority': String(priority || 3),
        'Tags': priority >= 4 ? 'warning' : 'white_check_mark',
      },
    });
    dbg(`push: ${res.status}`);
  } catch (e) { dbg(`push ERROR: ${e.message}`); }
}

function speak(text) {
  try {
    Bun.spawn([VOICE_BIN, 'speak', text], { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg(`voice speak: ${text.slice(0, 80)}`);
  } catch (e) { dbg(`voice speak ERROR: ${e.message}`); }
}

// ── Helpers de eventos ──────────────────────────────────────────────────
function sessionIdOf(event) {
  return event.properties?.sessionID || event.properties?.id
    || event.sessionID || event.id || '';
}

function messageText(m) {
  let text = '';
  for (const p of m.parts || []) {
    if (p.type === 'text' && p.text) text += p.text + ' ';
  }
  return text.replace(/\s+/g, ' ').trim();
}

async function fetchMessages(client, sessionID) {
  if (!client?.session?.messages || !sessionID) return null;
  let val;
  try { val = await client.session.messages({ path: { id: sessionID } }); }
  catch { return null; }
  const list = val?.data ?? val?.response ?? val;
  return Array.isArray(list) ? list : null;
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
  dbg('plugin init v3 (event-driven + notify_user tool)');
  return {
    tool: {
      notify_user: tool({
        description:
          'Avisa al usuario con una notificacion de escritorio, push al celular y (opcional) '
          + 'voz Chatterbox. Usala para informar en tus propias palabras cuando termines una '
          + 'tarea o cuando algo merezca atencion. Redacta el mensaje tu mismo, con contexto, '
          + 'en espanol claro y breve (1-2 frases).',
        args: {
          message: tool.schema.string().describe('Texto de la notificacion (espanol, breve, con contexto)'),
          title: tool.schema.string().optional().describe('Titulo corto de la notificacion'),
          priority: tool.schema.number().int().min(1).max(5).optional()
            .describe('Prioridad 1-5 (5 = urgente). Default 3'),
          speak: tool.schema.boolean().optional()
            .describe('Forzar lectura por Chatterbox aunque auto-speak este OFF'),
        },
        async execute(args, context) {
          const message = String(args.message || '').trim();
          if (!message) return 'Error: message vacio';
          const title = (args.title || 'opencode').trim();
          const priority = args.priority || 3;

          writeCache(LAST_MESSAGE_FILE, message);
          notifyDesktop(title, message);
          await push(title, message, priority);

          if (args.speak === true || autoSpeakEnabled()) {
            speak(message);
            return `Notificado y hablado: ${message}`;
          }
          dbg('notify_user: auto-speak OFF, solo notificacion visual/push');
          return `Notificado: ${message}`;
        },
      }),
    },

    event: async ({ event }) => {
      try {
        const sid = sessionIdOf(event);

        if (event.type === 'message.updated') {
          const list = await fetchMessages(client, sid);
          if (list) {
            for (let i = list.length - 1; i >= 0; i--) {
              if (list[i]?.info?.role !== 'assistant') continue;
              const t = messageText(list[i]);
              if (t) { writeCache(LAST_RESPONSE_FILE, t); break; }
            }
          }
          return;
        }

        if (event.type === 'permission.asked' || event.type === 'permission.updated') {
          if (alreadyFired('perm', sid)) return;
          const detail = (() => {
            try {
              const p = event.permission || event.properties || {};
              return p.request?.command || p.request?.tool || p.prompt
                || (p.pattern ? String(p.pattern) : '') || p.title || '';
            } catch { return ''; }
          })();
          notifyDesktop('opencode: permiso', detail || 'Pide permiso');
          await push('opencode: permiso', `Pide permiso: ${detail}`, 4);
          if (autoSpeakEnabled()) speak(`Pide permiso: ${detail || 'revisa opencode'}`);
          return;
        }

        if (event.type === 'session.error') {
          if (alreadyFired('error', sid)) return;
          const errMsg = String(event.properties?.error || event.error || 'Error desconocido').slice(0, 300);
          notifyDesktop('opencode: error', errMsg);
          await push('opencode: error', errMsg, 4);
          speak(`Error: ${errMsg}`);
          return;
        }
      } catch (e) {
        dbg(`event handler ERROR: ${e.message}`);
      }
    },
  };
};
