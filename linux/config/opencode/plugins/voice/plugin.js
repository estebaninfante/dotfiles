// voice — opencode plugin v2 (event-driven, sin timers)
//
// opencode NO ejecuta setInterval/setTimeout en plugins → todo es reactivo
// a eventos. Los archivos se escriben de forma sincrona en los handlers.
//
// Arquitectura:
//   1. message.updated  → guarda ultima respuesta del asistente en
//                          ~/.cache/voice/last-response.txt (para on-demand)
//   2. session.idle     → genera resumen (Groq o fallback), notifica,
//                          guarda en ~/.cache/voice/last-summary.txt,
//                          y habla si auto-speak esta ON
//   3. permission.asked → notificacion + push (habla si auto-speak ON)
//   4. session.error    → notificacion + push + habla
//
// On-demand (Hyprland Super+Shift+V → `voice summarize`):
//   El script lee ~/.cache/voice/last-summary.txt y lo habla via Chatterbox.
//
// Toggle auto-speak (Hyprland Super+Ctrl+V → `voice toggle`):
//   El script escribe ~/.local/state/opencode/voice-auto-speak ('1'/'0').
//   El plugin lo lee en cada evento (default '0' = OFF).
//
// Notificaciones: siempre notify-send + push ntfy. La VOZ es opcional.

import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'fs';

const DEBUG_LOG = process.env.VOICE_PLUGIN_LOG || '/tmp/opencode/voice-plugin.log';
const CACHE_DIR = `${process.env.HOME}/.cache/voice`;
const LAST_RESPONSE_FILE = `${CACHE_DIR}/last-response.txt`;
const LAST_SUMMARY_FILE = `${CACHE_DIR}/last-summary.txt`;
const AUTO_SPEAK_FILE = `${process.env.HOME}/.local/state/opencode/voice-auto-speak`;
const GROQ_KEY_FILE = `${process.env.HOME}/.local/state/opencode/notify-groq-key`;
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

function writeFile(path, text) {
  try {
    mkdirSync(CACHE_DIR, { recursive: true });
    writeFileSync(path, text);
  } catch (e) { dbg(`writeFile ${path} ERROR: ${e.message}`); }
}

// ── Toggles ─────────────────────────────────────────────────────────────
function autoSpeakEnabled() {
  try { return readFileSync(AUTO_SPEAK_FILE, 'utf8').trim() === '1'; }
  catch { return false; } // default OFF
}

function groqKey() {
  try { return readFileSync(GROQ_KEY_FILE, 'utf8').trim() || ''; }
  catch { return ''; }
}

// ── Event helpers ───────────────────────────────────────────────────────
function sessionIdOf(event) {
  return event.properties?.sessionID || event.properties?.id
    || event.sessionID || event.id || '';
}

function isSessionIdle(event) {
  if (event.type === 'session.idle') return true;
  if (event.type === 'session.status') {
    return event.properties?.status?.type === 'idle' || event.status?.type === 'idle';
  }
  return false;
}

function isPermissionAsked(event) {
  return event.type === 'permission.asked' || event.type === 'permission.updated';
}

function isSessionError(event) {
  return event.type === 'session.error';
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

// ── Session data ────────────────────────────────────────────────────────
async function sessionTitle(client, sessionID) {
  if (!client?.session?.get || !sessionID) return '';
  try {
    const res = await client.session.get({ path: { id: sessionID } });
    return res?.data?.title || '';
  } catch { return ''; }
}

async function fetchMessages(client, sessionID) {
  if (!client?.session?.messages || !sessionID) return null;
  let val;
  try { val = await client.session.messages({ path: { id: sessionID } }); }
  catch { return null; }
  const list = val?.data ?? val?.response ?? val;
  return Array.isArray(list) ? list : null;
}

function messageText(m) {
  let text = '';
  for (const p of m.parts || []) {
    if (p.type === 'text' && p.text) text += p.text + ' ';
  }
  return text.replace(/\s+/g, ' ').trim();
}

// Ultima respuesta del asistente (texto).
async function lastAssistantText(client, sessionID) {
  const list = await fetchMessages(client, sessionID);
  if (!list) return '';
  for (let i = list.length - 1; i >= 0; i--) {
    if (list[i]?.info?.role !== 'assistant') continue;
    const t = messageText(list[i]);
    if (t) return t;
  }
  return '';
}

// Transcripcion de la cola de la sesion (para el resumen Groq).
async function buildTranscript(client, sessionID) {
  const list = await fetchMessages(client, sessionID);
  if (!list) return '';
  const sorted = [...list].sort((a, b) =>
    (a?.info?.time?.created ?? 0) - (b?.info?.time?.created ?? 0));
  const out = [];
  for (const m of sorted) {
    const role = m?.info?.role;
    if (role !== 'user' && role !== 'assistant') continue;
    let text = '';
    for (const p of m.parts || []) {
      if (p.type === 'text' && p.text) text += p.text + ' ';
      else if (p.type === 'tool' && p.tool) text += `[tool:${p.tool}] `;
    }
    text = text.replace(/\s+/g, ' ').trim().slice(0, 400);
    if (text) out.push(`${role === 'user' ? 'Usuario' : 'Asistente'}: ${text}`);
  }
  return out.slice(-14).join('\n');
}

// ── Resumen via Groq ────────────────────────────────────────────────────
async function groqSummary(transcript, ctxTitle) {
  const key = groqKey();
  if (!key || !transcript) return '';
  const body = {
    model: 'openai/gpt-oss-20b',
    max_tokens: 500,
    temperature: 0.3,
    reasoning_effort: 'low',
    messages: [
      {
        role: 'system',
        content:
          'Eres un asistente que resume sesiones de un agente de codigo. '
          + 'Responde SIEMPRE en espanol tecnico SIMPLE, plano y directo. '
          + 'Una sola frase corta (maximo ~20 palabras) que diga QUE se hizo y SI funciono. '
          + 'Prioriza SIEMPRE lo MAS RECIENTE. Si hubo errores, dilo claramente. '
          + 'No des saludos ni explicaciones: solo la frase.',
      },
      {
        role: 'user',
        content: `Sesion${ctxTitle ? ` "${ctxTitle}"` : ''}. Mensajes recientes:\n${transcript}\n\nResume en una frase en espanol tecnico simple.`,
      },
    ],
  };
  try {
    const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) return '';
    const data = await res.json();
    return data?.choices?.[0]?.message?.content?.trim() || '';
  } catch { return ''; }
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

// ── Handlers ────────────────────────────────────────────────────────────
async function handleIdle(client, sid) {
  const title = await sessionTitle(client, sid);

  // Guardar ultima respuesta (cruda) por si el resumen falla.
  const lastText = await lastAssistantText(client, sid);
  if (lastText) writeFile(LAST_RESPONSE_FILE, lastText);

  // Resumen: transcript → Groq → fallback.
  let summary = '';
  const transcript = await buildTranscript(client, sid);
  if (transcript) summary = await groqSummary(transcript, title);
  if (!summary) summary = lastText ? lastText.slice(0, 300) : '';
  if (!summary) summary = title ? `Sesion "${title}" terminada` : 'Sesion terminada';

  writeFile(LAST_SUMMARY_FILE, summary);

  const notifTitle = title ? `opencode: ${title}` : 'opencode: sesion terminada';
  notifyDesktop(notifTitle, summary);
  await push('opencode', summary, 3);

  if (autoSpeakEnabled()) speak(summary);
  else dbg('auto-speak OFF, no speak');
}

export default async ({ client }) => {
  dbg('plugin init v2 (event-driven)');
  return {
    event: async ({ event }) => {
      try {
        const sid = sessionIdOf(event);

        if (event.type === 'message.updated') {
          // Guardar la ultima respuesta del asistente para on-demand.
          const list = await fetchMessages(client, sid);
          if (list) {
            for (let i = list.length - 1; i >= 0; i--) {
              if (list[i]?.info?.role !== 'assistant') continue;
              const t = messageText(list[i]);
              if (t) { writeFile(LAST_RESPONSE_FILE, t); break; }
            }
          }
          return;
        }

        if (isSessionIdle(event)) {
          if (alreadyFired('idle', sid)) return;
          dbg('session idle');
          await handleIdle(client, sid);
          return;
        }

        if (isPermissionAsked(event)) {
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

        if (isSessionError(event)) {
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
