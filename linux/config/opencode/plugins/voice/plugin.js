// voice — opencode plugin v2
//
// Arquitectura:
//   1. Eventos → notificaciones DINAMICAS (contenido real, no textos estaticos)
//   2. Auto-speak on idle → TOGGLEABLE (default OFF)
//   3. On-demand summary → via archivo de comando (~/.cache/voice/cmd/)
//
// Comandos (keybinding escribe archivo):
//   ~/.cache/voice/cmd/summarize  → resume ultima respuesta + habla via Chatterbox
//   ~/.cache/voice/cmd/toggle     → activar/desactivar auto-speak
//
// Toggles:
//   ~/.local/state/opencode/voice-auto-speak ('1' = hablar en idle, default '0')
//
// Notificaciones:
//   - Siempre via notify-send (contenido dinamico generado por el agente)
//   - Push via ntfy.sh (reutiliza patron de notify-sound)
//
// Chatterbox:
//   - Solo habla cuando auto-speak ON o cuando se ejecuta summarize on-demand
//   - Usa 'voice speak' que routea al daemon TTS

import { readFileSync, writeFileSync, appendFileSync, mkdirSync, existsSync, unlinkSync } from 'fs';
import { watch } from 'fs';

const DEBUG_LOG = process.env.VOICE_PLUGIN_LOG || '/tmp/opencode/voice-plugin.log';
const CMD_DIR = `${process.env.HOME}/.cache/voice/cmd`;
const CACHE_DIR = `${process.env.HOME}/.cache/voice`;
const AUTO_SPEAK_FILE = `${process.env.HOME}/.local/state/opencode/voice-auto-speak`;
const LAST_SUMMARY_FILE = `${CACHE_DIR}/last-summary.txt`;
const GROQ_KEY_FILE = `${process.env.HOME}/.local/state/opencode/notify-groq-key`;

const TOPIC = (() => {
  try {
    const m = readFileSync(`${process.env.HOME}/.config/machine-type`, 'utf8').trim();
    return m === 'desktop' ? 'opencode-desktop' : 'opencode-laptop';
  } catch { return 'opencode-laptop'; }
})();

function dbg(msg) {
  try {
    appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] [pid ${process.pid}] ${msg}\n`);
  } catch {}
}

// ── Toggles ─────────────────────────────────────────────────────────────
function autoSpeakEnabled() {
  try {
    return readFileSync(AUTO_SPEAK_FILE, 'utf8').trim() === '1';
  } catch {
    return false; // default OFF
  }
}

function setAutoSpeak(enabled) {
  try {
    mkdirSync(`${process.env.HOME}/.local/state/opencode`, { recursive: true });
    writeFileSync(AUTO_SPEAK_FILE, enabled ? '1' : '0');
    dbg(`auto-speak: ${enabled ? 'ON' : 'OFF'}`);
  } catch (e) {
    dbg(`setAutoSpeak ERROR: ${e.message}`);
  }
}

function groqKey() {
  try {
    return readFileSync(GROQ_KEY_FILE, 'utf8').trim() || '';
  } catch { return ''; }
}

// ── Session helpers ─────────────────────────────────────────────────────
function sessionIdOf(event) {
  return event.properties?.sessionID
    || event.properties?.id
    || event.sessionID
    || event.id
    || '';
}

async function sessionTitle(client, sessionID) {
  if (!client?.session?.get || !sessionID) return '';
  try {
    const res = await client.session.get({ path: { id: sessionID } });
    return res?.data?.title || '';
  } catch { return ''; }
}

function isSessionIdle(event) {
  if (event.type === 'session.idle') return true;
  if (event.type === 'session.status') {
    return event.properties?.status?.type === 'idle'
      || event.status?.type === 'idle';
  }
  return false;
}

function isPermissionAsked(event) {
  return event.type === 'permission.asked' || event.type === 'permission.updated';
}

function isSessionError(event) {
  return event.type === 'session.error';
}

// ── Dedup ───────────────────────────────────────────────────────────────
const recent = new Map();
function alreadyFired(kind, sid) {
  const key = `${kind}:${sid || 'nosid'}`;
  const now = Date.now();
  if (now - (recent.get(key) || 0) < 15000) return true;
  recent.set(key, now);
  if (recent.size > 64) for (const [k, t] of recent) if (now - t > 60000) recent.delete(k);
  return false;
}

// ── Transcript ──────────────────────────────────────────────────────────
async function fetchMessages(client, sessionID) {
  let res;
  try {
    res = client.session.messages({ path: { id: sessionID } });
  } catch { return null; }
  let val;
  try { val = await res; } catch { return null; }
  const list = val?.data ?? val?.response ?? val;
  return Array.isArray(list) ? list : null;
}

async function buildTranscript(client, sessionID) {
  if (!client?.session?.messages || !sessionID) return '';
  const list = await fetchMessages(client, sessionID);
  if (!list) return '';
  const sorted = [...list].sort((a, b) => {
    return (a?.info?.time?.created ?? 0) - (b?.info?.time?.created ?? 0);
  });
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

async function lastAssistantMessage(client, sessionID) {
  if (!client?.session?.messages || !sessionID) return '';
  const list = await fetchMessages(client, sessionID);
  if (!list) return '';
  // Find last assistant message with text
  for (let i = list.length - 1; i >= 0; i--) {
    const m = list[i];
    if (m?.info?.role !== 'assistant') continue;
    let text = '';
    for (const p of m.parts || []) {
      if (p.type === 'text' && p.text) text += p.text + ' ';
    }
    text = text.replace(/\s+/g, ' ').trim();
    if (text) return text.slice(0, 800);
  }
  return '';
}

// ── Summary via Groq ────────────────────────────────────────────────────
async function groqSummary(transcript, ctxTitle) {
  const key = groqKey();
  if (!key) return '';
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
          + 'Responde SIEMPRE en espanol tecnico SIMPLE, plano y directo, '
          + 'sin jerga innecesaria ni anglicismos evitables. '
          + 'Una sola frase corta (maximo ~20 palabras) que diga QUE se hizo y SI funciono. '
          + 'Prioriza SIEMPRE lo MAS RECIENTE: los ultimos mensajes del final son lo que cuenta. '
          + 'Si hubo errores, dilo claramente ("fallo", "quedo pendiente"). '
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

// ── Notifications ───────────────────────────────────────────────────────
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

function speak(summary) {
  try {
    Bun.spawn(['voice', 'speak', summary], { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg(`voice speak: ${summary.slice(0, 80)}`);
  } catch (e) { dbg(`voice speak ERROR: ${e.message}`); }
}

// ── File command handler ────────────────────────────────────────────────
// Keybinding escribe archivos en CMD_DIR para trigger on-demand
let activeSession = null;
let activeClient = null;

function handleCommand(filename) {
  const cmdPath = `${CMD_DIR}/${filename}`;
  if (!existsSync(cmdPath)) return;

  try {
    unlinkSync(cmdPath); // consume el comando

    if (filename === 'summarize') {
      dbg('CMD: summarize (on-demand)');
      if (!activeSession || !activeClient) {
        dbg('  no active session');
        notifyDesktop('voice', 'No hay sesion activa');
        return;
      }
      doSummary(activeClient, activeSession, true); // true = force speak
    } else if (filename === 'toggle') {
      const newState = !autoSpeakEnabled();
      setAutoSpeak(newState);
      notifyDesktop('voice', `Auto-speak: ${newState ? 'ON' : 'OFF'}`);
    } else if (filename === 'on') {
      setAutoSpeak(true);
      notifyDesktop('voice', 'Auto-speak: ON');
    } else if (filename === 'off') {
      setAutoSpeak(false);
      notifyDesktop('voice', 'Auto-speak: OFF');
    }
  } catch (e) {
    dbg(`CMD handler ERROR: ${e.message}`);
  }
}

async function doSummary(client, sessionID, forceSpeak = false) {
  try {
    const title = await sessionTitle(client, sessionID);
    const transcript = await buildTranscript(client, sessionID);
    let summary = '';

    if (transcript) {
      summary = await groqSummary(transcript, title);
    }
    if (!summary) {
      // Fallback: usar ultimo mensaje del asistente
      summary = await lastAssistantMessage(client, sessionID);
    }
    if (!summary) {
      summary = title ? `Sesion "${title}" terminada` : 'Sesion terminada';
    }

    // Guardar para referencia
    try {
      mkdirSync(CACHE_DIR, { recursive: true });
      writeFileSync(LAST_SUMMARY_FILE, summary);
    } catch {}

    // Notificacion dinamica (siempre)
    const notifTitle = title ? `opencode: ${title}` : 'opencode: sesion terminada';
    notifyDesktop(notifTitle, summary);

    // Push al celular
    await push('opencode', summary, 3);

    // Speak: solo si force (on-demand) o auto-speak enabled
    if (forceSpeak || autoSpeakEnabled()) {
      speak(summary);
    } else {
      dbg('auto-speak OFF, no speak');
    }
  } catch (e) {
    dbg(`doSummary ERROR: ${e.message}`);
  }
}

// ── Command file watcher ────────────────────────────────────────────────
function startCmdWatcher() {
  try {
    mkdirSync(CMD_DIR, { recursive: true });
  } catch {}

  // Poll cada 1s para detectar comandos
  setInterval(() => {
    try {
      const { readdirSync } = require('fs');
      const files = readdirSync(CMD_DIR);
      for (const f of files) {
        if (f.startsWith('.')) continue;
        handleCommand(f);
      }
    } catch {}
  }, 1000);

  dbg('cmd watcher started');
}

// ── Plugin entry ────────────────────────────────────────────────────────
export default async ({ $, client }) => {
  dbg('plugin init v2');
  startCmdWatcher();

  return {
    event: async ({ event }) => {
      try {
        const sid = sessionIdOf(event);

        // Track sesion activa para on-demand
        if (sid) {
          activeSession = sid;
          activeClient = client;
        }

        if (isSessionIdle(event)) {
          if (alreadyFired('idle', sid)) return;
          dbg('session idle');
          await doSummary(client, sid, false); // false = respect toggle
        } else if (isPermissionAsked(event)) {
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
        } else if (isSessionError(event)) {
          if (alreadyFired('error', sid)) return;
          const errMsg = event.properties?.error || event.error || 'Error desconocido';
          notifyDesktop('opencode: error', String(errMsg));
          speak(`Error: ${errMsg}`);
        }
      } catch (e) {
        dbg(`event handler ERROR: ${e.message}`);
      }
    },
  };
};
