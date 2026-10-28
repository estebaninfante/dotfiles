/**
 * leer — la respuesta completa, dicha en voz alta.
 *
 * El cierre de `tts-summary` habla UN resumen de una frase: sirve para avisar
 * que el agente terminó, no para estudiar escuchando. Cuando el usuario está
 * con audífonos y las manos ocupadas, lo que necesita es la respuesta entera,
 * en orden, sin mirar la pantalla.
 *
 * Acá vive lo que no necesita procesos ni audio (por eso se puede verificar):
 *
 *  - `limpiarParaOido`: deja el texto apto para el oído. Mismas reglas que
 *    `~/dotfiles/linux/voice/spoken.py` (que ya usa `voice think`), más lo que
 *    aparece en las respuestas de un agente y no se puede leer en voz alta:
 *    bloques y tablas de código, rutas largas, JSON, diffs, separadores.
 *
 *  - `trocearParaOido`: parte el texto en trozos que se puedan empezar a oír
 *    enseguida. Nunca corta una palabra y nunca deja un trozo vacío.
 *
 *  - `debeLeer`: la decisión (corrida cortada, voz apagada, texto vacío).
 */

/** Renglones que, leídos, solo hacen ruido: tablas, diffs, JSON, separadores. */
const RUIDO = [
  /^\s*\|.*\|\s*$/gm, // filas de tabla
  /^\s*[-=*_]{3,}\s*$/gm, // separadores
  /^\s*(diff --git|index [0-9a-f]{7}|\+\+\+|---)\s/gm, // diffs
  /^\s*[{}[\],;]+\s*$/gm, // llaves sueltas
];

/** Un token con forma de ruta, URL o hash: no se pronuncia. */
const TOKEN_MUDO = /\b(?:https?:\/\/\S+|~?\/[\w./-]{8,}|\b[0-9a-f]{12,}\b)/g;

export function limpiarParaOido(texto: string): string {
  let t = texto ?? "";
  t = t.replace(/```[\s\S]*?```/g, " "); // bloques de código
  t = t.replace(/~~~[\s\S]*?~~~/g, " ");
  t = t.replace(/<think[\s\S]*?<\/think>/gi, " "); // razonamiento
  t = t.replace(/<[^>]+>/g, " "); // HTML
  for (const re of RUIDO) t = t.replace(re, " ");
  t = t.replace(/`([^`]*)`/g, "$1"); // código inline: se dice
  t = t.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1"); // imágenes
  t = t.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1"); // links
  t = t.replace(/^\s{0,3}#{1,6}\s*/gm, ""); // títulos
  t = t.replace(/^\s*[-*+]\s+/gm, ""); // viñetas
  t = t.replace(/^\s*>\s?/gm, ""); // citas
  t = t.replace(/[*_#]+/g, "");
  t = t.replace(TOKEN_MUDO, " "); // rutas, URLs y hashes
  t = t.replace(/\s+/g, " ");
  return t.trim();
}

/** Corta un trozo demasiado largo por la última coma/espacio antes del tope. */
function partirLargo(frase: string, max: number): string[] {
  const partes: string[] = [];
  let resto = frase.trim();
  while (resto.length > max) {
    const ventana = resto.slice(0, max);
    const corte = Math.max(
      ventana.lastIndexOf(", "),
      ventana.lastIndexOf("; "),
      ventana.lastIndexOf(": "),
      ventana.lastIndexOf(" "),
    );
    // Sin espacio razonable (una palabra gigante): se corta igual, pero nunca
    // a mitad de palabra salvo que no haya alternativa.
    const en = corte > max * 0.4 ? corte + 1 : max;
    partes.push(resto.slice(0, en).trim());
    resto = resto.slice(en).trim();
  }
  if (resto) partes.push(resto);
  return partes.filter(Boolean);
}

/** Frases: corta donde termina la idea y sigue con mayúscula o fin. */
function separarFrases(texto: string): string[] {
  return texto
    .replace(/([.!?…])\s+/g, "$1\u0000")
    .split("\u0000")
    .map((f) => f.trim())
    .filter(Boolean);
}

/**
 * Trozos listos para el oído: el primero corto (para empezar a sonar ya) y el
 * resto agrupado, para no lanzar un proceso por frase.
 */
export function trocearParaOido(texto: string, max = 260, restoMax = 900): string[] {
  const t = (texto ?? "").trim();
  if (!t) return [];
  const frases = separarFrases(t);
  const trozos: string[] = [];
  let actual = "";
  const cerrar = (): void => {
    if (actual) trozos.push(actual);
    actual = "";
  };
  for (const frase of frases) {
    for (const parte of partirLargo(frase, max)) {
      if (!actual) actual = parte;
      else if (actual.length + 1 + parte.length <= max) actual += ` ${parte}`;
      else {
        cerrar();
        actual = parte;
      }
    }
  }
  cerrar();
  if (trozos.length <= 1) return trozos;
  // El primero se dice ya; los demás se juntan en bloques más grandes.
  const salida = [trozos[0]];
  let bloque = "";
  for (const trozo of trozos.slice(1)) {
    if (!bloque) bloque = trozo;
    else if (bloque.length + 1 + trozo.length <= restoMax) bloque += ` ${trozo}`;
    else {
      salida.push(bloque);
      bloque = trozo;
    }
  }
  if (bloque) salida.push(bloque);
  return salida;
}

export interface DecisionLectura {
  /** El interruptor propio (`leer on|off`) o el maestro de voz. */
  activada: boolean;
  /** La corrida entera se interrumpió. */
  abortada?: boolean;
  /** Algún turno de la corrida quedó con `stopReason` de interrupción. */
  turnoInterrumpido?: boolean;
  /** Lo que el asistente respondió. */
  texto?: string;
}

/** Se lee solo si el usuario no cortó y hay algo que decir. */
export function debeLeer(d: DecisionLectura): boolean {
  if (!d.activada) return false;
  if (d.abortada === true || d.turnoInterrumpido === true) return false;
  return limpiarParaOido(d.texto ?? "").length >= 2;
}
