// notify-sound — opencode plugin
//
// Notifica en dos canales:
//   1. Voz local (TTS Piper via `speak`) en:
//      - sesion idle         → la sesion termino
//      - permiso pedido      → opencode pide permiso para ejecutar
//   2. Push al celular via ntfy.sh:
//      - sesion idle         → "opencode: sesion terminada"
//      - permiso pedido      → "opencode: pide permiso" (prioridad alta)
//
// El push usa fetch nativo de Bun → sin dependencia de curl.
// El TTS usa `~/.local/bin/speak` (script del repo en linux/bin/speak,
// symlinkeado por home-manager; lee texto via argumento).
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

// Ruta absoluta a `speak` (evita depender del PATH del proceso).
const SPEAK = `${process.env.HOME}/.local/bin/speak`;

// dedup entre procesos: lock atomico via mkdir en /tmp, con TTL. 
// Varias instancias de opencode pueden recibir el mismo `session.idle`;
// solo habla la que gane el lock, el resto lo ignora.
import { mkdirSync, statSync, writeFileSync, rmSync, readFileSync, appendFileSync } from 'fs';

const LOCK_DIR = '/tmp/opencode/speak-locks';
const LOCK_TTL_MS = 90000; // 90s: suficiente para que la frase termine
const PUSH_STATE_FILE = `${process.env.HOME}/.local/state/opencode/notify-push-enabled`;

// Ausencia de estado conserva comportamiento actual: push activado.
function pushEnabled() {
  try {
    return readFileSync(PUSH_STATE_FILE, 'utf8').trim() !== '0';
  } catch {
    return true;
  }
}

function acquireLock(key) {
  try {
    const dir = `${LOCK_DIR}/${key}`;
    try {
      mkdirSync(dir, { recursive: false });
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const age = Date.now() - statSync(dir).mtimeMs;
      if (age > LOCK_TTL_MS) {
        rmSync(dir, { recursive: true, force: true });
        mkdirSync(dir, { recursive: false });
      } else {
        return false; // ocupado: otro proceso/evento ya hablo
      }
    }
    writeFileSync(`${dir}/pid`, String(process.pid));
    return () => {
      try { writeFileSync(`${dir}/ts`, String(Date.now())); } catch {}
    };
  } catch {
    return () => {};
  }
}

function dbg(msg) {
  try {
    appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] [pid ${process.pid}] ${msg}\n`);
  } catch {}
}

// Lee el texto en voz alta (Piper TTS). No bloquea: spawn + no await.
// opencode usa la voz es_MX-claude-high (espanol latino, femenina, Clara).
// `key` identifica el evento (sesion/permiso + sessionID) para el dedup.
//
// NOTA: el plugin plugins/voice/plugin.js es ahora el encargado del TTS
// (resumenes, anuncios). Este plugin mantiene SOLO el push a ntfy.sh para
// no duplicar la voz. Re-habilitar el TTS local aqui (p.ej. como fallback):
//   NOTIFY_SOUND_TTS=1
function speak(text, key) {
  if (process.env.NOTIFY_SOUND_TTS !== '1') { dbg(`tts off (voice plugin a cargo): ${key}`); return; }
  if (!key) { dbg(`speak (no key, skip): ${text}`); return; }
  const release = acquireLock(key);
  if (release === false) {
    dbg(`speak (dedup, skip): ${text}`);
    return;
  }
  try {
    Bun.spawn([SPEAK, '-v', 'es_MX-claude-high', text], { stdio: ['ignore', 'ignore', 'ignore'] });
    dbg(`speak: ${text}`);
  } catch (e) {
    dbg(`speak ERROR: ${e.message}`);
  } finally {
    release();
  }
}

// Push a ntfy.sh. Prioridad: 4 = alta (permiso), 3 = default (termino).
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
          speak(`Opencode: sesion terminada${ctx}`, `idle-${sid || 'default'}`);
          await push('opencode', `Sesion terminada${ctx}`, 3);
        } else if (isPermissionAsked(event)) {
          dbg('  → permission asked detected');
          const detail = permissionDetail(event);
          speak(`Opencode pide permiso para: ${detail || 'ejecutar'}`, `perm-${sid || 'default'}`);
          await push('opencode: permiso', `${detail ? `Pide permiso: ${detail}` : 'Pide permiso'}${ctx}`, 4);
        }
      } catch (e) {
        dbg(`handler ERROR: ${e.message}`);
      }
    },
  };
};
