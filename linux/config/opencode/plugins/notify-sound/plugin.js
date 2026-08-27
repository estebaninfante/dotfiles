// notify-sound — opencode plugin
//
// Notifica el fin de sesión con UN sonido agradable (sin voz):
//   1. Chime local via pw-play (freedesktop sound theme).
//   2. Push al celular via ntfy.sh (reutiliza patrón previo).
//
// Toggle del sonido local:
//   ~/.local/state/opencode/notify-sound-enabled   ('0' = apagado)
//   Ausente o cualquier otro valor → sonido activado.
//   El panel de NOTIFICACIONES de quickshell escribe este archivo.
//
// El push usa fetch nativo de Bun → sin dependencia de curl.
// El topico se configura en TOPIC.
//
// RESUMEN al terminar la sesión:
//   - Lee los mensajes de la sesion via SDK y pide a Groq
//     (llama-3.1-8b-instant) una sola frase en ESPAÑOL TÉCNICO SIMPLE
//     que diga qué se hizo y si funcionó.
//   - Sale siempre por notify-send; por voz SOLO si el toggle esta activo.
//   - Key: ~/.local/state/opencode/notify-groq-key (chmod 600, nunca repo).
//   - Sin key o si Groq falla → fallback: titulo + nº de mensajes.
//
// Toggles (el panel NOTIFICACIONES de quickshell los escribe):
//   ~/.local/state/opencode/notify-sound-enabled  ('0' = sin campana)
//   ~/.local/state/opencode/notify-voice-enabled  ('1' = hablar resumen;
//                                                  default apagado)
//   ~/.local/state/opencode/notify-push-enabled   ('0' = sin push ntfy)
//   Ausente u otro valor => comportamiento indicado arriba.
//
// Privacidad: el texto de la conversacion se envia a la nube de Groq
// para generar el resumen. Sin key no hay envio externo.
//
// NOTA sobre eventos (version-dependent):
//   - opencode deriva `session.idle` desde `session.status` (status.type
//     == "idle") en el cliente; el hook `event` del plugin puede recibir
//     el crudo (`session.status`) en vez del derivado (`session.idle`).
//     Por eso se manejan ambos, con dedup para no disparar doble.
//   - La SDK v1.18.x emite `permission.updated` para permisos pedidos
//     (la doc web dice `permission.asked`). Se manejan ambos.
//
// Suscripcion en el celular: abrir https://ntfy.sh/<TOPIC> o la app
// ntfy (Android/iOS) y agregar el topico.

const TOPIC = 'opencode-laptop';

const DEBUG_LOG = process.env.NOTIFY_SOUND_LOG || '/tmp/opencode/notify-sound.log';

import { readFileSync, appendFileSync } from 'fs';

const SOUND_STATE_FILE = `${process.env.HOME}/.local/state/opencode/notify-sound-enabled`;
const VOICE_STATE_FILE = `${process.env.HOME}/.local/state/opencode/notify-voice-enabled`;
const GROQ_KEY_FILE = `${process.env.HOME}/.local/state/opencode/notify-groq-key`;

// Sonido "lindo" para fin de tarea: completo/acierto del tema freedesktop.
const CHIME_FILE = process.env.NOTIFY_SOUND_FILE
  || '/run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga';

function soundEnabled() {
  try {
    return readFileSync(SOUND_STATE_FILE, 'utf8').trim() !== '0';
  } catch {
    return true; // sin estado → sonido activado
  }
}

// Voz del resumen: apagada por defecto (el usuario la activa en el panel).
function voiceEnabled() {
  try {
    return readFileSync(VOICE_STATE_FILE, 'utf8').trim() === '1';
  } catch {
    return false;
  }
}

function groqKey() {
  try {
    const k = readFileSync(GROQ_KEY_FILE, 'utf8').trim();
    return k || '';
  } catch {
    return '';
  }
}

// Ausencia de estado conserva comportamiento actual: push activado.
const PUSH_STATE_FILE = `${process.env.HOME}/.local/state/opencode/notify-push-enabled`;

function pushEnabled() {
  try {
    return readFileSync(PUSH_STATE_FILE, 'utf8').trim() !== '0';
  } catch {
    return true;
  }
}

function dbg(msg) {
  try {
    appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] [pid ${process.pid}] ${msg}\n`);
  } catch {}
}

// Reproduce el chime local (PipeWire primero, paplay como fallback).
// No bloquea: spawn + no await. El toggle se lee en cada evento.
function playChime() {
  if (!soundEnabled()) { dbg('sound off (toggle quickshell)'); return; }
  const cmd = ['pw-play', CHIME_FILE];
  try {
    Bun.spawn(cmd, { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg(`chime: ${CHIME_FILE}`);
  } catch (e) {
    dbg(`chime ERROR (${cmd[0]}): ${e.message}`);
    try {
      Bun.spawn(['paplay', CHIME_FILE], { stdio: ['ignore', 'ignore', 'ignore'] });
      dbg(`chime fallback: paplay`);
    } catch (e2) {
      dbg(`chime ERROR (paplay): ${e2.message}`);
    }
  }
}

// Push a ntfy.sh. Prioridad: 3 = default (termino), 4 = alta (permiso).
async function push(title, message, priority) {
  if (!pushEnabled()) {
    dbg(`push off: ${title}`);
    return;
  }
  try {
    dbg(`push: ${title} | ${message}`);
    const res = await fetch(`https://ntfy.sh/${TOPIC}`, {
      method: 'POST',
      body: message,
      headers: {
        'Title': title,
        'Priority': String(priority || 3),
        'Tags': priority >= 4 ? 'warning' : 'white_check_mark',
      },
    });
    dbg(`push resp: ${res.status}`);
  } catch (e) {
    dbg(`push ERROR: ${e.message}`);
  }
}

// Extrae el comando/tool del evento de permiso (defensivo: la forma del
// payload varia entre versiones). En la SDK v1.18.x, `permission.updated`
// trae `properties: Permission` = { id, type, pattern, title, ... }.
function permissionDetail(event) {
  try {
    const p = event.permission || event.properties || {};
    return p.request?.command
      || p.request?.tool
      || p.prompt
      || (p.pattern ? String(p.pattern) : '')
      || p.title
      || '';
  } catch {
    return '';
  }
}

// Deteccion de "sesion idle" tolerante a la forma del evento.
function isSessionIdle(event) {
  if (event.type === 'session.idle') return true;
  if (event.type === 'session.status') {
    return event.properties?.status?.type === 'idle'
      || event.status?.type === 'idle';
  }
  return false;
}

// Deteccion de "permiso pedido" tolerante a la forma del evento.
function isPermissionAsked(event) {
  return event.type === 'permission.asked' || event.type === 'permission.updated';
}

// sessionID del evento, tolerante a la forma.
function sessionIdOf(event) {
  return event.properties?.sessionID
    || event.properties?.id
    || event.sessionID
    || event.id
    || '';
}

// Titulo de la sesion via SDK client (session.get → Session.title).
async function sessionTitle(client, sessionID) {
  if (!client?.session?.get || !sessionID) return '';
  try {
    const res = await client.session.get({ path: { id: sessionID } });
    return res?.data?.title || '';
  } catch (e) {
    dbg(`sessionTitle ERROR: ${e.message}`);
    return '';
  }
}

// Dedup por (tipo, sessionID): idle llega como evento derivado Y crudo.
const recent = new Map();
function alreadyFired(kind, sid) {
  const key = `${kind}:${sid || 'nosid'}`;
  const now = Date.now();
  if (now - (recent.get(key) || 0) < 15000) return true;
  recent.set(key, now);
  if (recent.size > 64) for (const [k, t] of recent) if (now - t > 60000) recent.delete(k);
  return false;
}

// Transcripcion compacta de la sesion via SDK (client.session.messages).
// Forma esperada: [{ info: { role }, parts: [{ type:'text', text }] }].
// El resultado puede venir como array directo, promesa o RequestResult
// ({ data }) segun build de la SDK → se desenvuelve en capas.
async function fetchMessages(client, sessionID) {
  let res;
  try {
    res = client.session.messages({ path: { id: sessionID } });
  } catch (e1) {
    dbg(`messages(path) ERROR: ${e1.message}`);
    return null;
  }
  let val;
  try {
    val = await res;
  } catch (e2) {
    dbg(`messages(await) ERROR: ${e2.message}`);
    return null;
  }
  const list = val?.data ?? val?.response ?? val;
  if (!Array.isArray(list)) {
    dbg(`messages shape inesperado: ${Object.prototype.toString.call(list)} keys=${list && typeof list === 'object' ? Object.keys(list).slice(0, 6).join(',') : String(list)}`);
    return null;
  }
  return list;
}

async function buildTranscript(client, sessionID) {
  if (!client?.session?.messages || !sessionID) return '';
  const list = await fetchMessages(client, sessionID);
  if (!list || !Array.isArray(list)) return '';
  const out = [];
  for (const m of list) {
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
  // Solo la cola: lo ultimo es lo que importa para "como termino".
  const tail = out.slice(-14).join('\n');
  dbg(`transcript: ${list.length} msgs totales, ${out.length} usadas`);
  return tail;
}

async function groqSummary(transcript, ctxTitle) {
  const key = groqKey();
  if (!key) return '';
  const body = {
    model: 'llama-3.1-8b-instant',
    max_tokens: 120,
    temperature: 0.3,
    messages: [
      {
        role: 'system',
        content:
          'Eres un asistente que resume sesiones de un agente de código. '
          + 'Responde SIEMPRE en español técnico SIMPLE, plano y directo, '
          + 'sin jerga innecesaria ni anglicismos evitables. '
          + 'Una sola frase corta (máximo ~20 palabras) que diga QUÉ se hizo y SI funcionó. '
          + 'Si hubo errores, dilo claramente ("falló", "quedó pendiente"). '
          + 'No des saludos ni explicaciones: solo la frase.',
      },
      {
        role: 'user',
        content: `Sesión${ctxTitle ? ` "${ctxTitle}"` : ''}. Mensajes recientes:\n${transcript}\n\nResume en una frase en español técnico simple.`,
      },
    ],
  };
  try {
    const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const errTxt = (await res.text()).slice(0, 200);
      dbg(`groq HTTP ${res.status}: ${errTxt}`);
      return '';
    }
    const data = await res.json();
    const txt = data?.choices?.[0]?.message?.content?.trim() || '';
    dbg(`groq ok: ${txt}`);
    return txt;
  } catch (e) {
    dbg(`groq ERROR: ${e.message}`);
    return '';
  }
}

// Notificacion escrita local (siempre) + voz opcional (toggle panel).
function notifyDesktop(summary, ctxTitle) {
  const title = ctxTitle ? `opencode: ${ctxTitle}` : 'opencode: sesión terminada';
  try {
    Bun.spawn(['notify-send', '-t', '8000', title, summary], { stdio: ['ignore', 'ignore', 'ignore'] });
  } catch (e) {
    dbg(`notify-send ERROR: ${e.message}`);
  }
}

function speakIfEnabled(summary) {
  if (!voiceEnabled()) { dbg('voice off (toggle quickshell)'); return; }
  try {
    Bun.spawn(['voice', 'speak', summary], { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg('voice speak enviado');
  } catch (e) {
    dbg(`voice ERROR: ${e.message}`);
  }
}

export default async ({ $, client }) => {
  dbg('plugin init');
  return {
    event: async ({ event }) => {
      dbg(`event: ${event.type}`);
      try {
        const sid = sessionIdOf(event);
        const title = await sessionTitle(client, sid);
        const ctx = title ? ` [${title}]` : '';

        if (isSessionIdle(event)) {
          dbg('  → session idle detected');
          if (alreadyFired('idle', sid)) {
            dbg('  → dedup: idle ya procesado, skip');
            return;
          }
          playChime();

          // Resumen: transcripcion → Groq (si hay key) → notificar.
          const ctxTitle = title || '';
          let summary = '';
          const t = await buildTranscript(client, sid);
          if (t) summary = await groqSummary(t, ctxTitle);
          else dbg('sin transcripcion o sin mensajes → resumen fallback');
          if (!summary) {
            // Fallback sin nube (sin key, sin mensajes o Groq caido).
            summary = ctxTitle ? `Sesión "${ctxTitle}" terminada` : 'Sesión terminada';
          }
          notifyDesktop(summary, ctxTitle);
          speakIfEnabled(summary);

          await push('opencode', `Sesion terminada${ctx ? '' : ''}${summary ? ` — ${summary}` : ctx}`, 3);
        } else if (isPermissionAsked(event)) {
          if (alreadyFired('perm', sid)) return;
          dbg('  → permission asked detected');
          const detail = permissionDetail(event);
          await push('opencode: permiso', `${detail ? `Pide permiso: ${detail}` : 'Pide permiso'}${ctx}`, 4);
        }
      } catch (e) {
        dbg(`handler ERROR: ${e.message}`);
      }
    },
  };
};
