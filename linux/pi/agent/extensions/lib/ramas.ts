/**
 * Reglas de ramas y worktrees, sin tocar git.
 *
 * Acá vive todo lo que se puede decidir mirando el nombre del repo y el texto
 * de un comando: qué flujo tiene cada proyecto, dónde va su worktree, qué rama
 * base usa y si un comando de bash escribe en el árbol. Lo impuro (crear
 * worktrees, mergear, commitear) vive en `../worktrees.ts`.
 *
 * Tests: `node --test lib/ramas.test.ts`.
 */

export type Flujo = "main" | "developing" | "directo";

export interface RepoConfig {
  flujo?: Flujo;
  /** Nombre de la rama base. null/"" = la rama principal del repo (main, master...). */
  rama?: string;
}

export interface Config {
  flujoPorDefecto: Flujo;
  prefijoRama: string;
  repos: Record<string, RepoConfig>;
}

export interface Politica {
  repo: string;
  flujo: Flujo;
  /** Rama base: de acá sale el worktree y acá se mergea. null = rama principal. */
  base: string | null;
  exigeWorktree: boolean;
}

const FLUJOS: Flujo[] = ["main", "developing", "directo"];
const SUCIO = /[^A-Za-z0-9._-]+/g;

export function configNormalizada(raw: unknown): Config {
  const data = (raw ?? {}) as Record<string, unknown>;
  const flujo = data.flujoPorDefecto as Flujo;
  const prefijo = typeof data.prefijoRama === "string" ? data.prefijoRama.trim() : "";
  const repos: Record<string, RepoConfig> = {};
  const entrada = (data.repos ?? {}) as Record<string, Record<string, unknown>>;
  for (const [nombre, cfg] of Object.entries(entrada)) {
    const item: RepoConfig = {};
    const suyo = cfg?.flujo as Flujo | undefined;
    if (suyo && FLUJOS.includes(suyo)) item.flujo = suyo;
    const rama = cfg?.rama;
    if (typeof rama === "string" && rama.trim()) item.rama = rama.trim();
    repos[nombre] = item;
  }
  return {
    flujoPorDefecto: FLUJOS.includes(flujo) ? flujo : "main",
    prefijoRama: prefijo || "agente",
    repos,
  };
}

/** Qué se hace en un repo: el flujo, la rama base y si exige worktree. */
export function politicaDe(config: Config, repo: string): Politica {
  const suyo = config.repos[repo] ?? {};
  const flujo = suyo.flujo ?? config.flujoPorDefecto;
  const base = flujo === "directo" ? null : (suyo.rama ?? (flujo === "developing" ? "developing" : null));
  return { repo, flujo, base, exigeWorktree: flujo !== "directo" };
}

/** Un nombre de rama y de carpeta seguros, derivados de un texto libre. */
export function slug(texto: string, max = 40): string {
  const limpio = String(texto ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(SUCIO, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");
  return limpio.slice(0, max).replace(/-+$/g, "") || "trabajo";
}

/** Id corto a partir de un texto libre: las primeras palabras alcanzan. */
export function idCorto(texto: string, palabras = 4): string {
  const partes = slug(texto, 120).split("-").filter(Boolean).slice(0, palabras);
  return partes.join("-") || "trabajo";
}

/** Rama de trabajo para un id: `<prefijo>/<slug>`. */
export function ramaDe(config: Config, id: string): string {
  return `${config.prefijoRama}/${slug(id)}`;
}

/** Dónde vive el worktree: `<parent del repo>/.rig-worktrees/<repo>/<id>`. */
export function rutaWorktree(rutaRepo: string, id: string): string {
  const partes = normalizar(rutaRepo).split("/");
  const nombre = partes.pop() ?? "repo";
  const padre = partes.join("/") || "/";
  return `${padre}/.rig-worktrees/${nombre}/${slug(id)}`;
}

/** Resuelve `.`, `..` y `~` en una ruta absoluta o relativa a `cwd`. */
export function normalizar(ruta: string, cwd = "/", home = "/"): string {
  let texto = String(ruta ?? "").trim();
  if (!texto) return normalizar(cwd, "/", home);
  if (texto === "~") texto = home;
  else if (texto.startsWith("~/")) texto = `${home}/${texto.slice(2)}`;
  if (!texto.startsWith("/")) texto = `${cwd}/${texto}`;
  const salida: string[] = [];
  for (const parte of texto.split("/")) {
    if (!parte || parte === ".") continue;
    if (parte === "..") salida.pop();
    else salida.push(parte);
  }
  return `/${salida.join("/")}`;
}

/** true si `ruta` está dentro de `raiz` (o es la misma). */
export function dentroDe(raiz: string, ruta: string): boolean {
  const base = normalizar(raiz);
  const objetivo = normalizar(ruta);
  return objetivo === base || objetivo.startsWith(`${base}/`);
}

/**
 * Qué escribe un comando de bash, o null si no escribe nada. Devuelve un motivo
 * corto para poder explicarlo en el mensaje de bloqueo.
 */
export function mutacionDetectada(comando: string): string | null {
  const cmd = String(comando ?? "");
  const reglas: [RegExp, string][] = [
    [
      /\bgit\s+(?:-[^ ]+\s+)*(add|commit|checkout|switch|reset|restore|stash|merge|rebase|cherry-pick|revert|apply|am|rm|mv|clean|worktree|tag|init|filter-branch)\b/,
      "git que cambia el árbol",
    ],
    [/\bgit\s+branch\s+(?:-[dDmMcCf]|--delete|--move|--copy|--set-upstream)/, "git branch que cambia ramas"],
    [/\bgit\s+config\s+[^|;&]*\s--?(?:add|unset|replace-all)\b/, "git config que escribe"],
    [/\b(sed|perl|ruby)\s+(?:-\S+\s+)*-i/, "edición en el lugar (sed/perl -i)"],
    [/\b(tee|dd|truncate|patch)\b/, "escritura directa a un archivo"],
    [/\b(rm|rmdir|mv|cp|mkdir|touch|ln|chmod|chown)\b/, "movimiento de archivos"],
    [/(?:^|[^0-9&])>>?\s*[^\s&|;)]/, "redirección a un archivo"],
    [/\b(npm|pnpm|yarn|bun|cargo|uv|pip|poetry|composer)\s+(install|add|remove|uninstall|sync|update)\b/, "instalación de dependencias"],
  ];
  for (const [patron, motivo] of reglas) {
    const m = patron.exec(cmd);
    if (!m) continue;
    if (motivo === "redirección a un archivo" && />>?\s*\/dev\/null/.test(cmd)) continue;
    return motivo;
  }
  return null;
}

/**
 * true si el comando escribe en la copia principal del repo (`repo`), mirando
 * dónde corre (`cwd`) y a qué rutas apunta. Los comandos que se van a otro
 * lado (`cd ~/dotfiles && ...`, `> /tmp/x`) no cuentan.
 */
export function comandoMutaRepo(
  comando: string,
  opciones: { repo: string; cwd: string; home?: string },
): string | null {
  const motivo = mutacionDetectada(comando);
  if (!motivo) return null;
  const { repo, cwd } = opciones;
  const home = opciones.home ?? "/";

  const cds = [...String(comando).matchAll(/\bcd\s+(?:"([^"]+)"|'([^']+)'|([^\s&;|)]+))/g)]
    .map((m) => m[1] ?? m[2] ?? m[3])
    .filter(Boolean);
  if (cds.some((destino) => !dentroDe(repo, normalizar(destino, cwd, home)))) return null;

  const absolutas = [...String(comando).matchAll(/(?:^|[\s"'=<>(])(\/[^\s"'&;|)]*)/g)]
    .map((m) => m[1])
    .filter((ruta) => ruta !== "/dev/null");
  if (absolutas.length && !absolutas.some((ruta) => dentroDe(repo, ruta))) return null;

  return motivo;
}
