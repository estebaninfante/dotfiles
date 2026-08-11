// notify-sound — opencode plugin
//
// Notifica en dos canales:
//   1. Sonido local (paplay) en:
//      - sesion idle         → la sesion termino
//      - permiso pedido      → opencode pide permiso para ejecutar
//   2. Push al celular via ntfy.sh:
//      - sesion idle         → "opencode: sesion terminada"
//      - permiso pedido      → "opencode: pide permiso" (prioridad alta)
//
// El push usa fetch nativo de Bun → sin dependencia de curl, portable
// entre Fedora y NixOS. El topico se configura en TOPIC.
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

function dbg(msg) {
  try {
    Bun.write(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`, { append: true });
  } catch {}
}

const SOUNDS = {
  permission: '/usr/share/sounds/gnome/default/alerts/string.ogg',
  complete: '/usr/share/sounds/gnome/default/alerts/hum.ogg',
};

function play(file) {
  try {
    if (Bun.which('paplay')) {
      Bun.spawn(['paplay', file], { stdio: ['ignore', 'ignore', 'ignore'] });
    }
  } catch {}
}

// Push a ntfy.sh. Prioridad: 4 = alta (permiso), 3 = default (termino).
async function push(title, message, priority) {
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
          play(SOUNDS.complete);
          await push('opencode', `Sesion terminada${ctx}`, 3);
        } else if (isPermissionAsked(event)) {
          dbg('  → permission asked detected');
          play(SOUNDS.permission);
          const detail = permissionDetail(event);
          await push('opencode: permiso', `${detail ? `Pide permiso: ${detail}` : 'Pide permiso'}${ctx}`, 4);
        }
      } catch (e) {
        dbg(`handler ERROR: ${e.message}`);
      }
    },
  };
};
