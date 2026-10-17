/**
 * pensamiento — helpers puros del visor de pensamiento y de las tareas.
 *
 * Sin dependencias a propósito: los usan `conversar.ts` (subtítulos en vivo) y
 * `rig.ts` (id, título y resumen de pasos de cada tarea). Al ser puro se puede
 * probar solo con Node (≥ 23 ejecuta TypeScript sin compilar):
 *
 *   node linux/pi/agent/extensions/lib/pensamiento.ts
 *
 * Regla de oro: acá no se inventa texto ni se llama a nadie; solo se limpia,
 * se corta y se decide si un fragmento se puede leer.
 */

/** Palabras con las que no se puede terminar una oración legible: si el corte
 *  quedó ahí, el fragmento viene de código o de una frase partida. */
const CONECTORES_FINALES = new Set([
  "a", "al", "algo", "and", "antes", "as", "at", "be", "been", "being", "by",
  "como", "con", "contra", "de", "del", "desde", "donde", "e", "el", "en",
  "entre", "era", "es", "esa", "ese", "eso", "esta", "este", "esto", "for",
  "from", "fue", "ha", "hacia", "hasta", "if", "in", "into", "is", "it",
  "just", "la", "las", "le", "les", "lo", "los", "más", "mas", "mientras",
  "mi", "mis", "muy", "no", "o", "of", "on", "or", "para", "pero", "por",
  "porque", "que", "se", "según", "ser", "si", "sin", "so", "sobre", "son",
  "su", "sus", "that", "the", "then", "to", "tu", "un", "una", "uno", "when",
  "while", "with", "y", "ya",
]);

/** Recorta por caracteres respetando la última palabra completa. */
export function recortar(texto: string, max: number): string {
  const t = String(texto ?? "").replace(/\s+/g, " ").trim();
  if (t.length <= max) return t;
  const corte = t.slice(0, max);
  const espacio = corte.lastIndexOf(" ");
  return `${(espacio > max * 0.55 ? corte.slice(0, espacio) : corte).trimEnd()}…`;
}

/** ¿El contenido de un `code span` es código (se tira) o una palabra suelta
 *  que ayuda a leer (se conserva)? `speaking.json` se conserva; `foo()` no. */
export function esCodigoInline(texto: string): boolean {
  const t = String(texto ?? "").trim();
  if (!t) return true;
  if (/\s/.test(t)) return true;
  if (/[=<>{}()[\];]|=>|->|\/\/|::/.test(t)) return true;
  return t.length > 40;
}

/** Deja solo prosa: sin bloques de código, sin ANSI, sin URLs ni adornos.
 *  Conserva la puntuación y los saltos de línea (el llamador decide qué hacer
 *  con ellos). */
export function limpiarPensamiento(texto: string): string {
  let t = String(texto ?? "");
  t = t.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, " ");
  t = t.replace(/```[\s\S]*?(?:```|$)/g, " ");
  t = t.replace(/~~~[\s\S]*?(?:~~~|$)/g, " ");
  // El código inline que no se puede leer se cambia por "…": deja claro que
  // falta algo y no rompe la gramática de la oración ("while …").
  t = t.replace(/``([^`\n]*)``/g, (_m, c: string) =>
    esCodigoInline(c) ? " … " : ` ${String(c).trim()} `,
  );
  t = t.replace(/`([^`\n]*)`/g, (_m, c: string) =>
    esCodigoInline(c) ? " … " : ` ${String(c).trim()} `,
  );
  t = t.replace(/<\/?[a-zA-Z][^>]*>/g, " ");
  t = t.replace(/!\[[^\]]*\]\([^)]*\)/g, " ");
  t = t.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1");
  t = t.replace(/https?:\/\/\S+/g, " ");
  t = t.replace(/[│├└┌┐┘┬┴┼─━╭╮╰╯]{2,}/g, " ");
  return t.replace(/\r/g, "");
}

/** Heurística: ¿la oración es más código que prosa? */
export function esCodigo(oracion: string): boolean {
  const s = String(oracion ?? "").trim();
  if (!s) return true;
  const letras = (s.match(/[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]/g) ?? []).length;
  if (letras < 8) return true;
  const raros = (s.match(/[^\w\sÁÉÍÓÚÜÑáéíóúüñ.,;:!?¿¡"'’“”()\-–—]/g) ?? []).length;
  if (raros / s.length > 0.14) return true;
  if (
    /(=>|::|<\/?[a-z]+>|\b(const|let|var|import|export|function|return|class|def|npm|pnpm|sudo|curl)\b\s*[({])/i.test(
      s,
    )
  ) {
    return true;
  }
  if (/^[\w./~-]+\.(ts|tsx|js|mjs|json|py|sh|bash|md|toml|yaml|yml|css|html|lua|rs|go|java|c|cpp|h)$/i.test(s)) {
    return true;
  }
  return false;
}

/** ¿Vale la pena mostrar esta oración? Descarta fragmentos mínimos y cortes
 *  que terminan en conector ("Then drops frames while ."). */
export function oracionUtil(oracion: string): boolean {
  const limpio = String(oracion ?? "")
    .trim()
    .replace(/[.,;:!?…]+\s*$/g, "")
    .trim();
  const palabras = limpio.split(/\s+/).filter(Boolean);
  if (palabras.length < 4) return false;
  const ultima = palabras[palabras.length - 1]!.toLowerCase();
  if (CONECTORES_FINALES.has(ultima)) return false;
  return true;
}

/** Título corto y humano para una tarea, sin depender de otro modelo.
 *  Saca adjuntos, cortesías y el artículo inicial. */
export function tituloDePedido(pedido: string, max = 58): string {
  let t = limpiarPensamiento(pedido).replace(/\s+/g, " ").trim();
  t = t.replace(/^(?:\S*\/\S+|\S+\.(?:png|jpe?g|gif|webp|bmp|pdf))\s+/i, "");
  t = t.replace(
    /^(?:che|por favor|necesito que|necesito|quiero que|quiero|me gustaría que|me gustaria que|podrías|podrias|podés|podes|puedes|ayudame a|ayúdame a|vamos a|vamos|dale|hace|hacer)\s+/i,
    "",
  );
  t = t.replace(/^(?:el|la|los|las|un|una)\s+/i, "");
  t = t.replace(/^["'“”«»]+|["'“”«»]+$/g, "").trim();
  const oracion = /^(.{10,}?[.!?])(?:\s|$)/.exec(t);
  if (oracion && oracion[1]!.length <= max + 20) t = oracion[1]!;
  t = t.replace(/[.!?]+$/, "").trim();
  if (!t) t = "Tarea sin título";
  t = t.charAt(0).toUpperCase() + t.slice(1);
  return recortar(t, max);
}

/** Id corto y estable para una tarea: `T-` + 4 caracteres de tiempo + 2 al azar. */
export function idTarea(ahora = Date.now(), azar = Math.random()): string {
  const base = Math.floor(ahora)
    .toString(36)
    .toUpperCase()
    .slice(-4)
    .padStart(4, "0");
  const extra = Math.floor(azar * 1296)
    .toString(36)
    .toUpperCase()
    .padStart(2, "0");
  return `T-${base}${extra}`;
}

/** Una línea con lo esencial de una llamada a herramienta, para el trace. */
export function resumenEntrada(herramienta: string, entrada: unknown): string {
  const input = (entrada ?? {}) as Record<string, unknown>;
  const txt = (v: unknown) => String(v ?? "").replace(/\s+/g, " ").trim();
  switch (herramienta) {
    case "bash":
    case "powershell":
      return `$ ${recortar(txt(input.command), 110)}`;
    case "read":
    case "write":
    case "edit":
    case "ls":
      return recortar(txt(input.path) || ".", 110);
    case "grep":
      return recortar(
        `${txt(input.pattern)}${input.path ? ` en ${txt(input.path)}` : ""}`,
        110,
      );
    case "find":
      return recortar(
        [txt(input.pattern ?? input.glob), txt(input.path)].filter(Boolean).join(" en "),
        110,
      );
    case "hablar":
    case "avisar":
      return recortar(txt(input.mensaje), 110);
    case "buscar_web":
      return recortar(txt(input.consulta), 110);
    case "leer_pagina":
      return recortar(txt(input.url), 110);
    case "pedir_revision_humana":
      return recortar(`${txt(input.tipo)} ${txt(input.nombre)}`, 110);
    default: {
      const partes = Object.entries(input)
        .slice(0, 4)
        .map(([k, v]) => {
          const valor = typeof v === "string" ? v : (JSON.stringify(v) ?? "");
          return `${k}=${recortar(valor, 40)}`;
        });
      return recortar(partes.join(" "), 110) || herramienta;
    }
  }
}

/** Duración legible: `8s`, `3m 07s`, `1h 02m 03s`. */
export function formatoDuracion(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m ${String(s).padStart(2, "0")}s`;
  if (m > 0) return `${m}m ${String(s).padStart(2, "0")}s`;
  return `${s}s`;
}

// ---------------------------------------------------------------------------
// Verificación rápida: `node pensamiento.ts` (se ejecuta solo si es el módulo
// principal, así importarlo desde las extensiones no imprime nada).
// ---------------------------------------------------------------------------
const comoPrincipal =
  typeof process !== "undefined" &&
  !!process.argv?.[1] &&
  /pensamiento\.(ts|js|mjs)$/.test(process.argv[1]);

if (comoPrincipal) {
  const casos: Array<[string, boolean]> = [
    ["mantener actualizado antes de hablar y refrescar mientras espera", true],
    ["const x = 1;", false],
    ["Then drops frames while .", false],
    ["```ts\nconst x = 1\n```\nLa idea es simple: mostrar la oración entera.", true],
  ];
  for (const [texto, ok] of casos) {
    const limpio = limpiarPensamiento(texto).replace(/\s+/g, " ").trim();
    const util = !esCodigo(limpio) && oracionUtil(limpio);
    console.log(`${util === ok ? "ok  " : "FALLA"} ${JSON.stringify(texto)} -> ${JSON.stringify(limpio)}`);
  }
  console.log(`título: ${tituloDePedido("Necesito que el plugin de pi para ver el pensamiento lo mejores.")}`);
  console.log(`id: ${idTarea(1792269424000, 0.42)}`);
}
