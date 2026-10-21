/**
 * vigia (lógica) — detectar que un agente se está trabando ANTES de que siga
 * gastando tokens.
 *
 * Todo lo que decide vive acá y es puro: no toca red, ni archivos, ni la UI.
 * La extensión `vigia.ts` solo enchufa estos cálculos a los eventos de pi.
 * Así se puede probar con casos fijos (`node --test lib/vigia.test.ts`) y
 * ajustar los umbrales sin levantar una sesión.
 *
 * Tres detectores, de más barato a más caro:
 *
 * 1. **Bucle de llamadas** — la misma herramienta con los mismos argumentos
 *    fallando una y otra vez, o errores distintos pero con la misma firma.
 *    Se corta ANTES de ejecutar (`evaluarAntes` → la extensión bloquea).
 * 2. **Racha y prueba y error** — muchos fallos seguidos, o muchas estrategias
 *    distintas sin un solo éxito (el clásico "voy a probar otra cosa" eterno).
 * 3. **Presupuesto** — minutos, llamadas y costo por corrida. Avisa temprano y
 *    frena fuerte mucho más tarde, para no arruinar tareas largas legítimas.
 *
 * Nada de esto mira el texto que el modelo "dice" que hace: mira lo que hizo.
 */

// ---------------------------------------------------------------------------
// Huellas y firmas
// ---------------------------------------------------------------------------

/** Normaliza un texto para comparar llamadas parecidas pero no idénticas. */
export function normalizarTexto(texto: string): string {
  return String(texto ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?\b/g, "<fecha>")
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, "<uuid>")
    .replace(/\b[0-9a-f]{16,}\b/gi, "<hex>")
    .replace(/\b(?:pid|PID)[=: ]?\d+\b/g, "pid=<n>")
    .replace(/\s+/g, " ")
    .trim();
}

/** Valores que cambian en cada ejecución y no hacen distinta a una llamada. */
const CLAVES_VOLATILES = new Set(["timeout", "time", "timestamp", "nonce", "id", "requestid"]);

function entradaEstable(entrada: unknown): unknown {
  if (entrada === null || typeof entrada !== "object") {
    return typeof entrada === "string" ? normalizarTexto(entrada) : entrada;
  }
  if (Array.isArray(entrada)) return entrada.map(entradaEstable);
  const salida: Record<string, unknown> = {};
  for (const clave of Object.keys(entrada as Record<string, unknown>).sort()) {
    if (CLAVES_VOLATILES.has(clave.toLowerCase())) continue;
    const valor = (entrada as Record<string, unknown>)[clave];
    if (valor === undefined || valor === null || valor === "") continue;
    salida[clave] = entradaEstable(valor);
  }
  return salida;
}

/**
 * Huella de una llamada: dos llamadas con la misma huella son, a efectos de
 * "estás repitiendo lo mismo", la misma. Se recorta para que un archivo
 * gigante pegado en `write` no arme una huella de megabytes.
 */
export function huellaDe(nombre: string, entrada: unknown): string {
  let estable: string;
  try {
    estable = JSON.stringify(entradaEstable(entrada ?? {}));
  } catch {
    estable = String(entrada);
  }
  return `${nombre}:${normalizarTexto(estable ?? "").slice(0, 400)}`;
}

/** Línea de error con la que se reconoce "el mismo problema otra vez". */
const PISTAS_ERROR =
  /(error|failed|failure|fatal|panic|exception|cannot|can't|unable|not found|no such|denied|refused|timeout|timed out|traceback|ENOENT|EACCES|ECONNREFUSED|undefined is not|is not a function|segmentation)/i;

/**
 * Firma de un error: se queda con la línea más informativa y le borra lo que
 * cambia entre corridas (rutas, números de línea, números, direcciones).
 * `TypeError: x is not a function at foo.js:12:3` → `typeerror: x is not a function at foo.js`.
 */
export function firmaDeError(texto: string): string {
  const lineas = String(texto ?? "")
    .split("\n")
    .map((linea) => linea.trim())
    .filter(Boolean);
  if (!lineas.length) return "";

  const elegida =
    lineas.find((linea) => PISTAS_ERROR.test(linea) && !/^\s*at\s/.test(linea)) ??
    lineas.find((linea) => PISTAS_ERROR.test(linea)) ??
    lineas[0];

  return normalizarTexto(elegida)
    .toLowerCase()
    .replace(/(?:\/[\w.@+-]+)+\/([\w.@+-]+)/g, "$1") // rutas absolutas → archivo
    .replace(/:\d+(?::\d+)?/g, "") // :12:3
    .replace(/\b\d+(?:\.\d+)?(?:ms|s|m|kb|mb|gb)?\b/g, "<n>")
    .replace(/["'`][^"'`]{0,80}["'`]/g, "<x>")
    .slice(0, 140)
    .trim();
}

/** Resumen corto y legible de una llamada, para pulso y bitácora. */
export function resumenDeLlamada(nombre: string, entrada: unknown, max = 64): string {
  const recortar = (texto: unknown, tope = max) => {
    const limpio = String(texto ?? "").replace(/\s+/g, " ").trim();
    return limpio.length > tope ? `${limpio.slice(0, tope - 1)}…` : limpio;
  };
  const e = (entrada ?? {}) as Record<string, unknown>;
  if (nombre === "bash") return `bash: ${recortar(e.command, max + 16)}`;
  if (nombre === "read" || nombre === "write" || nombre === "edit") {
    return `${nombre}: ${recortar(e.path ?? e.file_path ?? e.archivo ?? "?")}`;
  }
  if (nombre === "worktree") {
    return `worktree ${String(e.accion ?? "")} ${String(e.id ?? e.ruta ?? "")}`.trim();
  }
  return `${nombre}: ${recortar(JSON.stringify(e))}`;
}

// ---------------------------------------------------------------------------
// Detector de bucles
// ---------------------------------------------------------------------------

export type Nivel = "ok" | "aviso" | "freno";

export interface Veredicto {
  nivel: Nivel;
  /** Clave estable de la regla que disparó (para no repetir el mismo aviso). */
  regla: string;
  /** Una frase corta para la barra o la notificación. */
  motivo: string;
  /** Qué decirle al modelo cuando se bloquea una llamada. */
  mensaje: string;
  /** Lo que ya se vio: "3 intentos iguales", "misma firma ×3". */
  detalle: string;
}

export interface Historial {
  huella: string;
  nombre: string;
  ok: boolean;
  firma?: string;
  resumen?: string;
  ts: number;
  /** Llamada bloqueada por vigia (no llegó a ejecutarse). */
  bloqueada?: boolean;
}

export interface OpcionesDetector {
  /** Ventana en la que se cuenta un patrón. */
  ventanaMs?: number;
  /** Cuántas veces puede fallar la MISMA llamada antes de bloquear la siguiente. */
  repeticionesError?: number;
  /** Cuántas veces puede aparecer la MISMA firma de error antes de frenar. */
  mismoError?: number;
  /** Fallos consecutivos antes de frenar. */
  rachaRoja?: number;
  /** Llamadas distintas sin un solo éxito que ya ameritan un aviso. */
  intentosSinExito?: number;
  /** Repeticiones exitosas de la misma llamada que merecen un aviso (no bloqueo). */
  repeticionesOk?: number;
}

const OPCIONES: Required<OpcionesDetector> = {
  ventanaMs: 10 * 60_000,
  repeticionesError: 2,
  mismoError: 3,
  rachaRoja: 8,
  intentosSinExito: 8,
  repeticionesOk: 6,
};

export class Detector {
  private readonly opciones: Required<OpcionesDetector>;
  readonly historial: Historial[] = [];
  /** Bloqueos seguidos sin que el agente cambie de enfoque. */
  bloqueosSeguidos = 0;
  private ultimoBloqueoMs = 0;

  constructor(opciones: OpcionesDetector = {}) {
    this.opciones = { ...OPCIONES, ...opciones };
  }

  get ventanaMs(): number {
    return this.opciones.ventanaMs;
  }

  private dentro(ts: number, ahora: number): boolean {
    return ahora - ts <= this.opciones.ventanaMs;
  }

  private recientes(ahora: number): Historial[] {
    return this.historial.filter((h) => this.dentro(h.ts, ahora) && !h.bloqueada);
  }

  /** Marca el inicio de una corrida: el historial no cruza pedidos del usuario. */
  reiniciar(): void {
    this.historial.length = 0;
    this.bloqueosSeguidos = 0;
    this.ultimoBloqueoMs = 0;
  }

  /**
   * ¿Conviene bloquear esta llamada antes de ejecutarla? No muta estado: el
   * llamador decide y, si bloquea, después llama a `registrarBloqueo`.
   */
  evaluarAntes(nombre: string, entrada: unknown, ahora = Date.now()): Veredicto | undefined {
    const huella = huellaDe(nombre, entrada);
    const recientes = this.recientes(ahora);
    const resumen = resumenDeLlamada(nombre, entrada);

    const iguales = recientes.filter((h) => h.huella === huella);
    const fallidas = iguales.filter((h) => !h.ok);
    if (fallidas.length >= this.opciones.repeticionesError) {
      const ultima = fallidas[fallidas.length - 1];
      return {
        nivel: "freno",
        regla: `misma-llamada:${huella.slice(0, 80)}`,
        motivo: `misma llamada fallida ×${fallidas.length}`,
        detalle: `${resumen}${ultima?.firma ? ` · último: ${ultima.firma}` : ""}`,
        mensaje:
          `VIGÍA bloqueó esta llamada: ya intentaste exactamente lo mismo ${fallidas.length} veces y falló. ` +
          `No la repitas. Cambiá de enfoque (otra herramienta, otro comando, leer el error completo) ` +
          `o llamá a la herramienta \`parte\` para dejar escrito qué intentabas y qué creés que pasa.`,
      };
    }

    const firma = this.firmaDominante(recientes, ahora);
    if (firma && firma.veces >= this.opciones.mismoError) {
      return {
        nivel: "freno",
        regla: `mismo-error:${firma.firma.slice(0, 80)}`,
        motivo: `mismo error ×${firma.veces}`,
        detalle: firma.firma,
        mensaje:
          `VIGÍA bloqueó esta llamada: el mismo error apareció ${firma.veces} veces ("${firma.firma}"). ` +
          `Seguir probando a ciegas no lo va a resolver. Pará, llamà a \`parte\` con tu diagnóstico ` +
          `(qué probaste, qué falló y cuál es tu hipótesis) y esperá indicaciones o cambiá de estrategia por completo.`,
      };
    }

    const racha = this.rachaDeFallos(recientes);
    if (racha >= this.opciones.rachaRoja) {
      return {
        nivel: "freno",
        regla: "racha-roja",
        motivo: `${racha} fallos seguidos`,
        detalle: `últimas: ${recientes.slice(-3).map((h) => h.resumen ?? h.nombre).join(" → ")}`,
        mensaje:
          `VIGÍA bloqueó esta llamada: llevás ${racha} fallos consecutivos sin un solo éxito. ` +
          `Algo estructural está mal (entorno, supuesto equivocado, archivo que no es). ` +
          `Pará y llamà a \`parte\` con lo que sabés o pedile ayuda al usuario.`,
      };
    }

    const distintas = new Set(recientes.map((h) => h.huella));
    if (
      recientes.length >= this.opciones.intentosSinExito &&
      distintas.size >= this.opciones.intentosSinExito &&
      recientes.every((h) => !h.ok)
    ) {
      return {
        nivel: "aviso",
        regla: "prueba-y-error",
        motivo: `${recientes.length} pruebas sin un solo éxito`,
        detalle: [...distintas].slice(-3).join(" | "),
        mensaje:
          `Llevás ${recientes.length} intentos distintos sin ningún éxito. Antes de seguir probando, ` +
          `dejá un \`parte\` con lo que descartaste y lo que creés que es.`,
      };
    }

    if (iguales.length >= this.opciones.repeticionesOk && iguales.every((h) => h.ok)) {
      return {
        nivel: "aviso",
        regla: `repeticion-ok:${huella.slice(0, 80)}`,
        motivo: `misma llamada exitosa ×${iguales.length}`,
        detalle: resumen,
        mensaje: `Repetiste ${iguales.length} veces ${resumen} sin avanzar. ¿Hace falta de nuevo?`,
      };
    }

    return undefined;
  }

  /** Anota el resultado real de una llamada ejecutada. */
  registrar(nombre: string, entrada: unknown, ok: boolean, textoError = "", ahora = Date.now()): void {
    this.historial.push({
      huella: huellaDe(nombre, entrada),
      nombre,
      ok,
      firma: ok ? undefined : firmaDeError(textoError),
      resumen: resumenDeLlamada(nombre, entrada),
      ts: ahora,
    });
    if (ok) this.bloqueosSeguidos = 0;
    this.podar(ahora);
  }

  /** Anota una llamada que vigia no dejó ejecutar. */
  registrarBloqueo(nombre: string, entrada: unknown, ahora = Date.now()): void {
    this.bloqueosSeguidos += 1;
    this.ultimoBloqueoMs = ahora;
    this.historial.push({
      huella: huellaDe(nombre, entrada),
      nombre,
      ok: false,
      resumen: resumenDeLlamada(nombre, entrada),
      ts: ahora,
      bloqueada: true,
    });
    this.podar(ahora);
  }

  /** Cuántas veces apareció ya esta firma de error en la ventana. */
  contarFirma(firma: string, ahora = Date.now()): number {
    if (!firma) return 0;
    return this.recientes(ahora).filter((h) => !h.ok && h.firma === firma).length;
  }

  /** Un éxito real (no un read) baja la racha de frustración. */
  private rachaDeFallos(recientes: Historial[]): number {
    let racha = 0;
    for (let i = recientes.length - 1; i >= 0; i -= 1) {
      if (recientes[i].ok) break;
      racha += 1;
    }
    return racha;
  }

  private firmaDominante(recientes: Historial[], ahora: number): { firma: string; veces: number } | undefined {
    const cuenta = new Map<string, number>();
    for (const h of recientes) {
      if (h.ok || !h.firma) continue;
      if (!this.dentro(h.ts, ahora)) continue;
      cuenta.set(h.firma, (cuenta.get(h.firma) ?? 0) + 1);
    }
    let mejor: { firma: string; veces: number } | undefined;
    for (const [firma, veces] of cuenta) {
      if (!mejor || veces > mejor.veces) mejor = { firma, veces };
    }
    return mejor;
  }

  private podar(ahora: number): void {
    const limite = ahora - this.opciones.ventanaMs * 2;
    while (this.historial.length && this.historial[0].ts < limite) this.historial.shift();
    if (this.historial.length > 400) this.historial.splice(0, this.historial.length - 400);
  }

  /** Cuántas llamadas se registraron en la ventana, para la barra. */
  llamadasEnVentana(ahora = Date.now()): number {
    return this.recientes(ahora).length;
  }

  erroresEnVentana(ahora = Date.now()): number {
    return this.recientes(ahora).filter((h) => !h.ok).length;
  }
}

// ---------------------------------------------------------------------------
// Presupuesto
// ---------------------------------------------------------------------------

export interface Limites {
  /** Minutos de corrida antes de avisar. El freno duro llega a 1.5×. */
  minutos: number;
  /** Llamadas a herramientas antes de avisar (freno duro a 1.5×). */
  llamadas: number;
  /** Costo en dólares antes de avisar (freno duro a 1.5×). */
  costo: number;
}

export const LIMITES_POR_DEFECTO: Limites = {
  minutos: 40,
  llamadas: 250,
  costo: 5,
};

/** Por debajo de esto no se dice nada. */
const AVISO = 0.7;
/** A partir de acá se frena de verdad (salvo herramientas de reporte). */
const FRENO = 1.5;

export interface EstadoPresupuesto {
  nivel: Nivel;
  fraccion: number;
  limite: keyof Limites;
  motivo: string;
}

export class Presupuesto {
  inicio = 0;
  llamadas = 0;
  costo = 0;
  tokens = 0;

  iniciar(ahora = Date.now()): void {
    this.inicio = ahora;
    this.llamadas = 0;
    this.costo = 0;
    this.tokens = 0;
  }

  /** Suma el uso de una respuesta del modelo. */
  sumarUso(uso?: { totalTokens?: number; cost?: { total?: number } } | null): void {
    if (!uso) return;
    if (Number.isFinite(uso.totalTokens)) this.tokens += Number(uso.totalTokens);
    if (Number.isFinite(uso.cost?.total)) this.costo += Number(uso.cost?.total);
  }

  sumarLlamada(): void {
    this.llamadas += 1;
  }

  minutos(ahora = Date.now()): number {
    return this.inicio ? Math.max(0, (ahora - this.inicio) / 60_000) : 0;
  }

  fracciones(ahora = Date.now()): Record<keyof Limites, number> {
    return {
      minutos: this.minutos(ahora) / Math.max(1, this.limites.minutos),
      llamadas: this.llamadas / Math.max(1, this.limites.llamadas),
      costo: this.costo / Math.max(0.01, this.limites.costo),
    };
  }

  /** Los límites vigentes; la extensión los puede cambiar en caliente. */
  limites: Limites = { ...LIMITES_POR_DEFECTO };

  estado(ahora = Date.now()): EstadoPresupuesto {
    const f = this.fracciones(ahora);
    const [limite, fraccion] = (Object.entries(f) as [keyof Limites, number][]).sort((a, b) => b[1] - a[1])[0];
    const nivel: Nivel = fraccion >= FRENO ? "freno" : fraccion >= AVISO ? "aviso" : "ok";
    const valor =
      limite === "minutos"
        ? `${this.minutos(ahora).toFixed(0)} de ${this.limites.minutos} min`
        : limite === "llamadas"
          ? `${this.llamadas} de ${this.limites.llamadas} llamadas`
          : `$${this.costo.toFixed(2)} de $${this.limites.costo.toFixed(2)}`;
    return { nivel, fraccion, limite, motivo: valor };
  }
}

// ---------------------------------------------------------------------------
// Estancamiento y formato
// ---------------------------------------------------------------------------

/**
 * ¿Hace mucho que mueve herramientas pero no cambia nada? No alcanza con
 * contar errores: un agente puede pasarse 15 minutos mirando logs sin tocar un
 * archivo. Eso merece que el usuario se entere, no un bloqueo automático.
 */
export function estaEstancado(datos: {
  minutosSinAvance: number;
  llamadasSinAvance: number;
  llamadasTotales: number;
  errores: number;
}): boolean {
  return (
    datos.llamadasTotales >= 12 &&
    datos.minutosSinAvance >= 10 &&
    datos.llamadasSinAvance >= 12 &&
    datos.errores > 0
  );
}

/** `12m · 34 llamadas · 3 err · 48k tok · $0.12` */
export function lineaEstado(datos: {
  minutos: number;
  llamadas: number;
  errores: number;
  tokens: number;
  costo: number;
}): string {
  const partes = [`${Math.floor(datos.minutos)}m`, `${datos.llamadas} llam`];
  if (datos.errores > 0) partes.push(`${datos.errores} err`);
  if (datos.tokens > 0) partes.push(`${formatoTokens(datos.tokens)} tok`);
  if (datos.costo > 0) partes.push(`$${datos.costo.toFixed(datos.costo < 0.1 ? 3 : 2)}`);
  return partes.join(" · ");
}

/** Tokens legibles: `950`, `3.4k`, `1.2M`. */
export function formatoTokens(n: number): string {
  if (!Number.isFinite(n) || n <= 0) return "0";
  if (n < 1000) return String(Math.round(n));
  if (n < 1_000_000) {
    const miles = n / 1000;
    return `${miles < 10 ? miles.toFixed(1) : Math.round(miles)}k`.replace(".0k", "k");
  }
  const millones = n / 1_000_000;
  return `${millones < 10 ? millones.toFixed(1) : Math.round(millones)}M`.replace(".0M", "M");
}
