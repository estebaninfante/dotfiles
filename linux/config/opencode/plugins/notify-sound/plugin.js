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
// NOTA sobre eventos (version-dependent):
//   - opencode deriva `session.idle` desde `session.status` (status.type
//     == "idle") en el cliente; el hook `event` del plugin puede recibir
//     el crudo (`session.status`) en vez del derivado (`session.idle`).
//     Por eso se manejan ambos.
//   - La SDK v1.18.x emite `permission.updated` para permisos pedidos
//     (la doc web dice `permission.asked`). Se manejan ambos.
//
// Suscripcion en el celular: abrir https://ntfy.sh/<TOPIC> o la app
// ntfy (Android/iOS) y agregar el topico.

const TOPIC = 'opencode-laptop';

const DEBUG_LOG = process.env.NOTIFY_SOUND_LOG || '/tmp/opencode/notify-sound.log';

import { readFileSync, appendFileSync } from 'fs';

const SOUND_STATE_FILE = `${process.env.HOME}/.local/state/opencode/notify-sound-enabled`;

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
          playChime();
          await push('opencode', `Sesion terminada${ctx}`, 3);
        } else if (isPermissionAsked(event)) {
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
