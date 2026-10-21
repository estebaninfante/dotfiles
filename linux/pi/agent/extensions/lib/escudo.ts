/**
 * La parte pura del escudo: qué hacer cuando una extensión tira una excepción
 * que nadie atrapó.
 *
 * Pi muere si eso pasa (lo registra en `crashes.json` y termina). Una sesión de
 * agente no debería caerse porque una extensión opcional —hablar, un correo,
 * una barra— falló: se pierde el turno, el contexto y, si estaba mergeando, el
 * trabajo a medias.
 */
export interface Registrable {
  on(evento: string, manejador: (motivo: unknown) => void): unknown;
}

export type Escritor = (linea: string) => void;

function describir(motivo: unknown): string {
  if (motivo instanceof Error) return `${motivo.name}: ${motivo.message}`;
  if (typeof motivo === "string") return motivo;
  try {
    return JSON.stringify(motivo);
  } catch {
    return String(motivo);
  }
}

export function instalarEscudo(
  proceso: Registrable,
  escribir: Escritor,
  ahora: () => string = () => new Date().toISOString(),
): void {
  const anotar = (que: string, motivo: unknown): void => {
    escribir(`${ahora()} ${que} · ${describir(motivo)}`);
  };
  proceso.on("uncaughtException", (motivo) => anotar("excepción sin atrapar", motivo));
  proceso.on("unhandledRejection", (motivo) => anotar("promesa rechazada sin manejar", motivo));
}
