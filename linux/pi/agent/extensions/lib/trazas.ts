/**
 * trazas — el árbol de tickets de una sesión, en texto y en Markdown.
 *
 * Regla del rig: un agente vivo = un ticket raíz abierto; cada pedido del
 * usuario = un subticket; cada delegación (subagente) = otro subticket. Acá
 * viven las funciones puras que arman ese árbol y lo vuelven legible para el
 * usuario, sin depender del estado global ni de la UI.
 *
 * Se prueban solas:
 *
 *   node --test linux/pi/agent/extensions/lib/trazas.test.ts
 */

import { formatoDuracion, recortar } from "./pensamiento.ts";

export type TipoTarea = "sesion" | "pedido" | "subtarea";
export type EstadoTarea = "activa" | "lista" | "cerrada";
export type TipoPaso = "pedido" | "tool" | "pensamiento" | "nota";

export interface Paso {
  /** ISO de cuándo empezó el paso. */
  t: string;
  tipo: TipoPaso;
  resumen: string;
  nombre?: string;
  /** id de la llamada, para engancharle el resultado cuando vuelve. */
  id?: string;
  ok?: boolean;
  ms?: number;
  resultado?: string;
}

export interface Tarea {
  id: string;
  titulo: string;
  pedido: string;
  creado: string;
  actualizado: string;
  hasta?: string;
  estado: EstadoTarea;
  session?: string;
  sessionId?: string;
  pasos: Paso[];
  /** Ticket padre. Vacío en el ticket raíz de la sesión. */
  padre?: string;
  /** sesion = ticket raíz (un agente vivo); pedido = lo que pidió el usuario;
   *  subtarea = delegación creada por el agente. */
  tipo?: TipoTarea;
  /** Sesión dueña: un ticket no se trabaja desde dos agentes a la vez. */
  dueno?: string;
  /** Nombre del agente que lo trabaja. */
  agente?: string;
}

export interface OpcionesTraza {
  /** Hora de referencia para calcular duraciones (tests). */
  ahora?: number;
  /** Pasos máximos por ticket en el texto (default 40). */
  maxPasos?: number;
  /** Recorte de cada línea de paso (default 160). */
  maxLinea?: number;
}

export function hijosDe(items: Tarea[], id: string): Tarea[] {
  return items
    .filter((t) => t.padre === id)
    .sort((a, b) => a.creado.localeCompare(b.creado));
}

/** ¿Es el ticket raíz de un agente (la sesión)? */
export function esRaiz(t: Tarea): boolean {
  return t.tipo === "sesion" || !t.padre;
}

/** Sube por los padres hasta el ticket raíz. Corta si hay un ciclo. */
export function raizDe(items: Tarea[], t: Tarea): Tarea {
  let actual = t;
  const vistos = new Set<string>();
  while (actual.padre && !vistos.has(actual.id)) {
    vistos.add(actual.id);
    const padre = items.find((x) => x.id === actual.padre);
    if (!padre) break;
    actual = padre;
  }
  return actual;
}

/** Todos los descendientes de un ticket, en profundidad. */
export function descendientesDe(items: Tarea[], id: string): Tarea[] {
  const out: Tarea[] = [];
  const vistos = new Set<string>();
  const visitar = (padre: string) => {
    for (const hijo of hijosDe(items, padre)) {
      if (vistos.has(hijo.id)) continue;
      vistos.add(hijo.id);
      out.push(hijo);
      visitar(hijo.id);
    }
  };
  visitar(id);
  return out;
}

/** Raíces (una por agente/sesión), de la más vieja a la más nueva. */
export function raicesDe(items: Tarea[]): Tarea[] {
  return items.filter(esRaiz).sort((a, b) => a.creado.localeCompare(b.creado));
}

/** Tickets de una sesión concreta: por sessionId o por la ruta del archivo.
 *  Incluye todo el subárbol de las raíces que pertenecen a esa sesión, aunque
 *  un subticket no repita el sessionId. */
export function deLaSesion(
  items: Tarea[],
  sessionId?: string,
  session?: string,
): Tarea[] {
  const propias = items.filter(
    (t) =>
      (sessionId && (t.sessionId === sessionId || t.dueno === sessionId)) ||
      (!sessionId && session && t.session === session),
  );
  const out = new Map<string, Tarea>();
  for (const t of propias) out.set(t.id, t);
  for (const t of propias.filter(esRaiz)) {
    for (const d of descendientesDe(items, t.id)) out.set(d.id, d);
  }
  return [...out.values()].sort((a, b) => {
    if (esRaiz(a) !== esRaiz(b)) return esRaiz(a) ? -1 : 1;
    return a.creado.localeCompare(b.creado) || a.id.localeCompare(b.id);
  });
}

function duracion(t: Tarea, ahora = Date.now()): string {
  const fin = t.hasta ? Date.parse(t.hasta) : ahora;
  const ms = fin - Date.parse(t.creado);
  return formatoDuracion(Number.isFinite(ms) ? ms : 0);
}

function simbolo(estado: EstadoTarea): string {
  if (estado === "activa") return "▶";
  if (estado === "lista") return "✓";
  return "■";
}

function iconoPaso(p: Paso): string {
  if (p.tipo === "pedido") return "▶";
  if (p.tipo === "pensamiento") return "💭";
  if (p.tipo === "nota") return "·";
  return p.ok === false ? "✗" : p.ok ? "✓" : "…";
}

function hora(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? "--:--:--"
    : d.toLocaleTimeString("es-AR", { hour12: false });
}

/**
 * Árbol compacto, una línea por ticket. La raíz va sin prefijo y los hijos se
 * indentan con `├─`/`└─` para que se pueda seguir el trazo de un vistazo.
 */
export function lineasArbol(
  items: Tarea[],
  raizId: string,
  ahora = Date.now(),
): string[] {
  const raiz = items.find((t) => t.id === raizId);
  if (!raiz) return [];
  const out: string[] = [];
  const caminar = (t: Tarea, prefijo: string, ultimo: boolean, nivel: number) => {
    const marca = nivel === 0 ? "" : `${prefijo}${ultimo ? "└─" : "├─"}`;
    const pasos = t.pasos.length ? ` · ${t.pasos.length} pasos` : "";
    out.push(
      `${marca}${t.id} ${simbolo(t.estado)} ${t.titulo} · ${t.estado} · ${duracion(t, ahora)}${pasos}`,
    );
    const hijos = hijosDe(items, t.id);
    const siguiente = nivel === 0 ? "" : `${prefijo}${ultimo ? "   " : "│  "}`;
    hijos.forEach((h, i) => caminar(h, siguiente, i === hijos.length - 1, nivel + 1));
  };
  caminar(raiz, "", true, 0);
  return out;
}

function trazaPasos(t: Tarea, opts: OpcionesTraza): string[] {
  const max = Math.max(4, opts.maxPasos ?? 40);
  const lineas: string[] = [];
  const pasos = t.pasos;
  const mostrar = pasos.length <= max ? pasos : [...pasos.slice(0, max - 8), null, ...pasos.slice(-8)];
  for (const p of mostrar) {
    if (p === null) {
      lineas.push(`  … ${pasos.length - (max - 8) - 8} paso(s) más`);
      continue;
    }
    const nombre = p.nombre ? `${p.nombre} ` : "";
    const ms = p.ms != null ? ` (${p.ms}ms)` : "";
    lineas.push(
      `  ${hora(p.t)} ${iconoPaso(p)} ${nombre}${recortar(p.resumen, opts.maxLinea ?? 160)}${ms}`,
    );
    if (p.resultado) {
      lineas.push(`        ↳ ${recortar(p.resultado, opts.maxLinea ?? 160)}`);
    }
  }
  return lineas;
}

/**
 * Trace legible de un ticket y sus descendientes: lo pedido, las herramientas,
 * los resultados y las delegaciones. Es lo mismo que el usuario ve en `/tarea`
 * y en el Markdown de la sesión.
 */
export function textoTraza(t: Tarea, items: Tarea[] = [], opts: OpcionesTraza = {}): string {
  const fuente = items.length ? items : [t];
  const actual = fuente.find((x) => x.id === t.id) ?? t;
  const raiz = raizDe(fuente, actual);
  const lineas: string[] = [];
  if (raiz.id !== actual.id) lineas.push(`raíz: ${raiz.id} · ${raiz.titulo}`);
  const secciones = [actual, ...descendientesDe(fuente, actual.id)];
  for (const [i, seccion] of secciones.entries()) {
    const prefijo = i === 0 ? "" : i === 1 ? "  " : "  ".repeat(1 + (i > 1 ? 1 : 0));
    if (i > 0) lineas.push("");
    lineas.push(
      `${prefijo}TICKET ${seccion.id} · ${seccion.titulo}`,
      `${prefijo}estado: ${seccion.estado} · ${duracion(seccion, opts.ahora)} · ${seccion.pasos.length} pasos`,
      `${prefijo}pedido: ${recortar(seccion.pedido, 400)}`,
    );
    if (seccion.agente) lineas.push(`${prefijo}agente: ${seccion.agente}`);
    lineas.push(...trazaPasos(seccion, opts).map((l) => `${prefijo}${l}`));
  }
  return lineas.join("\n");
}

function tituloMd(t: Tarea): string {
  return `${t.id} · ${t.titulo}`;
}

/**
 * Documento Markdown de una sesión completa. Se escribe en
 * `~/.local/share/pi/trazas/<raíz>.md` después de cada paso, así el usuario
 * puede abrirlo con cualquier editor y seguir toda la historia sin mirar JSON.
 */
export function markdownTraza(
  raiz: Tarea,
  items: Tarea[],
  opts: OpcionesTraza = {},
): string {
  const ahora = opts.ahora ?? Date.now();
  const arbol = [raiz, ...descendientesDe(items, raiz.id)];
  const lineas: string[] = [
    `# Traza ${raiz.id} · ${raiz.titulo}`,
    "",
    `- **agente:** ${raiz.agente || "sin nombre"}`,
    `- **estado:** ${raiz.estado}`,
    `- **abierta:** ${raiz.creado}`,
    `- **actualizada:** ${raiz.actualizado}`,
    `- **duración:** ${duracion(raiz, ahora)}`,
    `- **tickets:** ${arbol.length} (1 sesión + ${arbol.length - 1} subtickets)`,
  ];
  if (raiz.session) lineas.push(`- **sesión:** \`${raiz.session}\``);
  if (raiz.dueno) lineas.push(`- **dueño:** \`${raiz.dueno}\``);
  lineas.push(
    "",
    "## Árbol",
    "",
    "```",
    ...lineasArbol(items, raiz.id, ahora),
    "```",
    "",
    "## Detalle",
  );

  const caminar = (t: Tarea, nivel: number) => {
    lineas.push("", `${"#".repeat(Math.min(6, nivel + 2))} ${tituloMd(t)}`, "");
    lineas.push(
      `- estado: **${t.estado}** · ${duracion(t, ahora)} · ${t.pasos.length} pasos`,
    );
    if (t.tipo && t.tipo !== "sesion") lineas.push(`- tipo: ${t.tipo}`);
    if (t.agente) lineas.push(`- agente: ${t.agente}`);
    if (t.padre) lineas.push(`- padre: ${t.padre}`);
    lineas.push("", `> ${recortar(t.pedido, 600)}`, "");
    lineas.push(...trazaPasos(t, opts));
    for (const hijo of hijosDe(items, t.id)) caminar(hijo, nivel + 1);
  };
  caminar(raiz, 0);
  lineas.push("", "---", `_Generado por el rig el ${new Date(ahora).toISOString()}_`);
  return `${lineas.join("\n")}\n`;
}

/** Índice de sesiones para abrir la traza que interesa sin buscar archivos. */
export function indiceMarkdown(items: Tarea[], ahora = Date.now()): string {
  const roots = raicesDe(items);
  const lineas = [
    "# Trazas de agentes",
    "",
    "Una línea por sesión. El archivo de cada una vive en esta misma carpeta.",
    "",
    "| ticket | agente | estado | tickets | actualizada | archivo |",
    "| --- | --- | --- | --- | --- | --- |",
  ];
  for (const r of [...roots].reverse()) {
    const n = 1 + descendientesDe(items, r.id).length;
    const agente = (r.agente || "sin nombre").replace(/\|/g, "/");
    const titulo = r.titulo.replace(/\|/g, "/");
    lineas.push(
      `| ${r.id} ${titulo} | ${agente} | ${r.estado} | ${n} | ${r.actualizado} | [${r.id}](./${r.id}.md) |`,
    );
  }
  if (!roots.length) lineas.push("| — | — | — | — | — | — |");
  lineas.push("", `_Actualizado ${new Date(ahora).toISOString()}_`);
  return `${lineas.join("\n")}\n`;
}
