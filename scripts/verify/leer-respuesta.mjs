#!/usr/bin/env node
/**
 * verify/leer-respuesta.mjs — arnés de la extensión `leer` (sin audio).
 *
 * Monta un `pi` de mentira con los eventos que la extensión escucha, dispara
 * corridas y compara lo que habría dicho. No toca el sistema de voz: la
 * extensión corre con PI_LEER_DRY=1 y escribe en un archivo temporal.
 */
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const EXT = join(process.env.HOME ?? "", "dotfiles/linux/pi/agent/extensions/leer.ts");
const quiet = process.argv.includes("--quiet");
const ok = (msg) => !quiet && console.log(`  ok    ${msg}`);
let fallas = 0;
const falla = (msg) => {
  fallas += 1;
  console.log(`  FALLA ${msg}`);
};

/** Un `pi` mínimo: guarda handlers por evento y respuestas emitidas al bus. */
function piFalso() {
  const handlers = new Map();
  const emitidos = [];
  return {
    on(evento, fn) {
      if (!handlers.has(evento)) handlers.set(evento, []);
      handlers.get(evento).push(fn);
    },
    registerTool() {},
    events: { emit: (evento, data) => emitidos.push({ evento, data }), on() {} },
    async disparar(evento, payload = {}) {
      for (const fn of handlers.get(evento) ?? []) await fn(payload, {});
    },
    emitidos,
  };
}

const bloqueTexto = (text) => ({ type: "text", text });

/** Corre la extensión con un entorno dado y una corrida guionada. */
async function correr({ activado = true, subagente = false, aborted = false, turnoInterrumpido = false, texto }) {
  const dir = mkdtempSync(join(tmpdir(), "leer-verify-"));
  const dry = join(dir, "dicho.log");
  const cfg = join(dir, "leer.json");
  writeFileSync(cfg, JSON.stringify({ activado }));
  process.env.PI_LEER_DRY = "1";
  process.env.PI_LEER_DRY_FILE = dry;
  process.env.PI_LEER_CONFIG = cfg;
  if (subagente) process.env.PI_SUBAGENT = "1";
  else delete process.env.PI_SUBAGENT;

  const { default: leer } = await import(`${EXT}?v=${Math.random()}`);
  const pi = piFalso();
  leer(pi);

  await pi.disparar("session_start");
  if (turnoInterrumpido) {
    await pi.disparar("message_end", {
      message: { role: "assistant", stopReason: "aborted", content: [bloqueTexto(texto)] },
    });
  }
  const antesDelCierre = pi.emitidos.length;
  await pi.disparar("turn_end", {
    message: { role: "assistant", content: [bloqueTexto(texto)] },
  });
  const avisosEnTurnEnd = pi.emitidos.length - antesDelCierre;
  await pi.disparar("agent_settled", { aborted });

  return {
    dicho: existsSync(dry) ? readFileSync(dry, "utf8") : "",
    emitidos: pi.emitidos,
    avisosEnTurnEnd,
  };
}

const RESPUESTA = [
  "Listo, ya está arreglado.",
  "",
  "El problema era el actualizador: mataba el servidor interno y después no",
  "podía instalar el paquete.",
  "",
  "```bash",
  "voice stop",
  "```",
  "",
  "Mirá https://ejemplo.com/muy/largo si querés el detalle.",
].join("\n");

// 1) corrida normal: se dice entera, limpia, y se anuncia al bus.
{
  const r = await correr({ texto: RESPUESTA });
  try {
    assert.match(r.dicho, /Listo, ya está arreglado/);
    assert.match(r.dicho, /no podía instalar el paquete/);
    assert.equal(r.dicho.includes("```"), false, "el bloque de código no se dice");
    assert.equal(r.dicho.includes("https://"), false, "la URL no se dice");
    assert.equal(
      r.emitidos.some((e) => e.evento === "voz:hablado"),
      true,
      "tiene que anunciar por el bus para que el cierre no repita",
    );
    // El anuncio va en `turn_end`, no en el cierre: así no depende del orden de
    // carga de las extensiones (tts-summary consume la lista en agent_settled).
    assert.equal(r.avisosEnTurnEnd >= 1, true, "el aviso al bus sale en turn_end");
    assert.equal(
      r.avisosEnTurnEnd <= 1,
      true,
      "se anuncia una sola vez por corrida, no por turno",
    );
    ok("la respuesta completa se dice, sin código ni URLs");
  } catch (e) {
    falla(`respuesta completa: ${e.message}`);
  }
}

// 2) el usuario cortó la corrida: silencio.
{
  const r = await correr({ texto: RESPUESTA, aborted: true });
  try {
    assert.equal(r.dicho, "", "no se lee una corrida cortada");
    // El aviso al bus puede haber salido en `turn_end` (ahí todavía no se sabe
    // que el usuario va a cortar). No molesta: si se corta, nadie habla — ni
    // esta extensión ni el cierre de tts-summary.
    ok("una corrida cortada no se lee");
  } catch (e) {
    falla(`corrida cortada: ${e.message}`);
  }
}

// 3) turno interrumpido aunque el cierre diga que no.
{
  const r = await correr({ texto: RESPUESTA, turnoInterrumpido: true });
  try {
    assert.equal(r.dicho, "", "no se lee un turno interrumpido");
    ok("un turno interrumpido no se lee");
  } catch (e) {
    falla(`turno interrumpido: ${e.message}`);
  }
}

// 4) apagada a mano.
{
  const r = await correr({ texto: RESPUESTA, activado: false });
  try {
    assert.equal(r.dicho, "", "con leer off no se dice nada");
    ok("con la lectura apagada no se dice nada");
  } catch (e) {
    falla(`lectura apagada: ${e.message}`);
  }
}

// 5) subagente: no habla.
{
  const r = await correr({ texto: RESPUESTA, subagente: true });
  try {
    assert.equal(r.dicho, "", "un subagente no habla");
    ok("un subagente no habla");
  } catch (e) {
    falla(`subagente: ${e.message}`);
  }
}

if (fallas) {
  console.log(`leer-respuesta: ${fallas} falla(s)`);
  process.exit(1);
}
console.log("leer-respuesta: ok");
