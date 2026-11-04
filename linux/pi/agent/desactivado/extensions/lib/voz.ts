/**
 * Lanzar el sistema de voz (`voice avisar`) sin poder tumbar la sesión.
 *
 * Un `spawn` no avisa de un binario inexistente por excepción: el error llega
 * como evento `'error'` del hijo, asíncrono. Sin listener, Node (y con él pi)
 * muere con un `uncaughtException` por un ENOENT: pasó cuando el sync de
 * dotfiles reescribía el symlink de `~/.local/bin/voice` y mató dos sesiones de
 * agente a mitad de trabajo. Hablar es opcional; morir por no poder hablar, no.
 */
import { spawn } from "node:child_process";

export interface OpcionesVoz {
  /** Binario a usar. Por defecto, el del sistema de voz del equipo. */
  bin?: string;
  /** De dónde viene el aviso (el nombre del agente). */
  source?: string;
  /** Para probar sin lanzar nada. */
  home?: string;
}

/** Lanza `voice avisar` en segundo plano. Nunca tira ni rechaza. */
export function avisarPorVoz(linea: string, opciones: OpcionesVoz = {}): boolean {
  return lanzar(["avisar"], linea, opciones);
}

/**
 * Lanza `voice say` en segundo plano: lectura directa, sin pasar por la entrega
 * (`avisar` puede diferir al buzón; leer una respuesta es inmediato). Va por el
 * mismo daemon, así la tecla de Windows (`voice stop`) corta la lectura igual
 * que cualquier otro mensaje, y el micrófono de Omar espera a que termine.
 */
export function decirPorVoz(texto: string, opciones: OpcionesVoz = {}): boolean {
  return lanzar(["say"], texto, opciones);
}

function lanzar(verbo: string[], texto: string, opciones: OpcionesVoz): boolean {
  const home = opciones.home ?? process.env.HOME ?? "";
  const bin = opciones.bin ?? process.env.PI_TTS_VOICE_BIN ?? `${home}/.local/bin/voice`;
  const source = opciones.source ?? "pi";
  try {
    const hijo = spawn(bin, [...verbo, "--source", source, "--", texto], {
      detached: true,
      stdio: "ignore",
    });
    // El listener es la mitad del arreglo: sin él, el ENOENT asíncrono mata el
    // proceso entero. Con él, la frase simplemente no se dice.
    hijo.on("error", () => {});
    hijo.unref();
    return true;
  } catch {
    return false;
  }
}
