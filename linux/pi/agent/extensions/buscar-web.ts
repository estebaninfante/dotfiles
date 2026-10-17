/**
 * buscar-web — búsqueda en internet para pi.
 *
 * Agrega dos tools:
 *   - `buscar_web`: busca en DuckDuckGo y devuelve título, URL y resumen.
 *   - `leer_pagina`: abre una URL y devuelve su texto legible.
 *
 * Y, en cada arranque de turno, inyecta una sección de sistema
 * (`<busqueda_web>`) con la política: buscar antes de responder, sobre todo
 * cuando hay dudas o cuando el dato puede haber cambiado. Además las tools
 * traen `promptGuidelines`, así la regla viaja con la declaración de la tool.
 *
 * No necesita claves ni dependencias: usa `fetch` y el endpoint HTML público
 * de DuckDuckGo. Si DuckDuckGo no devuelve resultados, cae al Instant Answer
 * API como respaldo.
 *
 * Config (opcional, por entorno):
 *   PI_BUSCAR_UA       User-Agent para las requests
 *   PI_BUSCAR_LIMITE   resultados por defecto (1-10, default 6)
 */

import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const UA =
  process.env.PI_BUSCAR_UA ??
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36";

const LIMITE_DEFAULT = Math.min(10, Math.max(1, Number(process.env.PI_BUSCAR_LIMITE) || 6));

/** Política que se inyecta en el system prompt en cada turno. */
const POLITICA = `Antes de responder, buscá en internet. Usá \`buscar_web\` como paso previo por defecto y \`leer_pagina\` para abrir las fuentes.
Hacelo siempre que:
- el usuario te explique algo que no entendés, o de lo que no estás seguro;
- el tema pueda haber cambiado (versiones, precios, noticias, lanzamientos, APIs, personas, eventos, clima);
- necesites confirmar un dato antes de afirmarlo.
Ante la duda, buscá primero y respondé después. Citá las URL que uses. Si la búsqueda no aclara, decilo con claridad en vez de inventar.
Excepción: si la respuesta depende solo de archivos locales que ya leíste o de una operación sobre el repositorio, podés resolverla sin buscar.`;

interface Resultado {
  title: string;
  url: string;
  snippet: string;
}

function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(Number.parseInt(h, 16)));
}

function stripTags(s: string): string {
  return decodeEntities(s.replace(/<[^>]*>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

/** Convierte un link de DuckDuckGo (`//duckduckgo.com/l/?uddg=...`) en la URL real. */
function urlReal(href: string): string {
  const m = href.match(/[?&]uddg=([^&]+)/);
  if (m) {
    try {
      return decodeURIComponent(m[1]);
    } catch {
      return href;
    }
  }
  if (href.startsWith("//")) return "https:" + href;
  return href;
}

function parseDuckDuckGo(html: string, limite: number): Resultado[] {
  const links: { url: string; title: string; at: number }[] = [];
  const linkRe = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  let m: RegExpExecArray | null;
  while ((m = linkRe.exec(html))) {
    links.push({ url: urlReal(m[1]), title: stripTags(m[2]), at: m.index });
  }

  const snips: { text: string; at: number }[] = [];
  const snipRe = /<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)<\/a>/g;
  while ((m = snipRe.exec(html))) {
    snips.push({ text: stripTags(m[1]), at: m.index });
  }

  return links.slice(0, limite).map((l) => {
    const snip = snips.find((s) => s.at > l.at);
    return { title: l.title, url: l.url, snippet: snip ? snip.text : "" };
  });
}

async function buscar(consulta: string, limite: number, signal?: AbortSignal): Promise<Resultado[]> {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(consulta)}&kl=ar-es`;
  const res = await fetch(url, {
    headers: { "User-Agent": UA, "Accept-Language": "es-AR,es;q=0.9,en;q=0.8" },
    signal: signal ?? AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`DuckDuckGo respondió HTTP ${res.status}`);
  const html = await res.text();
  const resultados = parseDuckDuckGo(html, limite);
  if (resultados.length > 0) return resultados;
  return instantAnswer(consulta, limite, signal);
}

/** Respaldo: Instant Answer API (bueno para datos factuales). */
async function instantAnswer(consulta: string, limite: number, signal?: AbortSignal): Promise<Resultado[]> {
  const url = `https://api.duckduckgo.com/?q=${encodeURIComponent(consulta)}&format=json&no_html=1&no_redirect=1`;
  const res = await fetch(url, { headers: { "User-Agent": UA }, signal: signal ?? AbortSignal.timeout(15000) });
  if (!res.ok) return [];
  const data: any = await res.json();
  const out: Resultado[] = [];
  if (data.AbstractText) {
    out.push({
      title: data.Heading || consulta,
      url: data.AbstractURL || `https://duckduckgo.com/?q=${encodeURIComponent(consulta)}`,
      snippet: String(data.AbstractText),
    });
  }
  for (const topic of data.RelatedTopics ?? []) {
    if (out.length >= limite) break;
    if (topic.Text && topic.FirstURL) out.push({ title: topic.Text.slice(0, 120), url: topic.FirstURL, snippet: topic.Text });
  }
  return out;
}

function htmlATexto(html: string): string {
  return decodeEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
      .replace(/<(nav|header|footer|aside|form|svg|template)[\s\S]*?<\/\1>/gi, " ")
      .replace(/<\/(p|div|li|h[1-6]|tr|section|article|blockquote)>/gi, "\n")
      .replace(/<br\s*\/?>/gi, "\n"),
  )
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

async function leer(url: string, max: number, signal?: AbortSignal): Promise<string> {
  const res = await fetch(url, {
    headers: { "User-Agent": UA, "Accept-Language": "es,en;q=0.8" },
    redirect: "follow",
    signal: signal ?? AbortSignal.timeout(25000),
  });
  if (!res.ok) throw new Error(`la página respondió HTTP ${res.status}`);
  const ct = res.headers.get("content-type") ?? "";
  const cuerpo = await res.text();
  const texto = ct.includes("html") || cuerpo.trimStart().startsWith("<") ? htmlATexto(cuerpo) : cuerpo;
  if (texto.length > max) {
    return `${texto.slice(0, max)}\n\n[…recortado a ${max} caracteres]`;
  }
  return texto;
}

function formatear(consulta: string, resultados: Resultado[]): string {
  if (resultados.length === 0) return `Sin resultados para «${consulta}».`;
  const cuerpo = resultados
    .map((r, i) => `${i + 1}. ${r.title}\n   ${r.url}\n   ${r.snippet || "(sin resumen)"}`)
    .join("\n\n");
  return `Resultados para «${consulta}»:\n\n${cuerpo}`;
}

export default function buscarWeb(pi: ExtensionAPI) {
  pi.registerTool({
    name: "buscar_web",
    label: "Buscar en internet",
    description:
      "Busca en internet (DuckDuckGo) y devuelve resultados con título, URL y resumen. " +
      "Usala ANTES de responder cuando no estés seguro, cuando el usuario te explique " +
      "algo que no entendés, o cuando el dato pueda haber cambiado (versiones, precios, " +
      "noticias, APIs, personas, eventos). Para leer una fuente en detalle, usá `leer_pagina`.",
    promptSnippet: "Buscar en internet y devolver resultados con URL",
    promptGuidelines: [
      "Ante cualquier duda, o si el usuario te explica algo que no entendés, buscá en " +
        "internet con `buscar_web` antes de responder.",
      "Buscá también cuando el dato pueda haber cambiado: versiones, precios, noticias, " +
        "lanzamientos, APIs, personas, eventos, clima.",
      "Citá las URL que uses. Si la búsqueda no aclara, decilo; no inventes.",
      "Para leer una fuente en detalle, abrila con `leer_pagina`.",
    ],
    parameters: Type.Object({
      consulta: Type.String({ description: "Qué buscar en internet" }),
      limite: Type.Optional(
        Type.Number({ description: `Cuántos resultados devolver (1-10, por defecto ${LIMITE_DEFAULT})` }),
      ),
    }),
    async execute(_toolCallId, params, signal) {
      const consulta = String(params.consulta ?? "").trim();
      if (!consulta) {
        return { content: [{ type: "text", text: "Falta la consulta." }], details: undefined };
      }
      const limite = Math.min(10, Math.max(1, Number(params.limite) || LIMITE_DEFAULT));
      try {
        const resultados = await buscar(consulta, limite, signal);
        return {
          content: [{ type: "text", text: formatear(consulta, resultados) }],
          details: { consulta, resultados },
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text", text: `No pude buscar «${consulta}»: ${msg}` }], details: undefined };
      }
    },
  });

  pi.registerTool({
    name: "leer_pagina",
    label: "Leer una página web",
    description:
      "Abre una URL y devuelve su texto legible (sin HTML). Usala para leer en detalle " +
      "una fuente que encontraste con `buscar_web`, o cuando el usuario te pasa un link.",
    promptSnippet: "Abrir una URL y devolver su texto legible",
    promptGuidelines: [
      "Para leer en detalle una fuente encontrada con `buscar_web`, o un link que pasó " +
        "el usuario, usá `leer_pagina`.",
    ],
    parameters: Type.Object({
      url: Type.String({ description: "URL http(s) a leer" }),
      maxCaracteres: Type.Optional(
        Type.Number({ description: "Máximo de caracteres a devolver (por defecto 8000)" }),
      ),
    }),
    async execute(_toolCallId, params, signal) {
      const url = String(params.url ?? "").trim();
      if (!/^https?:\/\//i.test(url)) {
        return { content: [{ type: "text", text: "La URL tiene que empezar con http:// o https://" }], details: undefined };
      }
      const max = Math.min(50000, Math.max(500, Number(params.maxCaracteres) || 8000));
      try {
        const texto = await leer(url, max, signal);
        return {
          content: [{ type: "text", text: texto || "(la página no devolvió texto legible)" }],
          details: { url, caracteres: texto.length },
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text", text: `No pude leer ${url}: ${msg}` }], details: undefined };
      }
    },
  });

  // Política permanente: viaja en cada request, no depende de que la tool esté activa.
  pi.on("before_agent_start", (event) => {
    const activas = event.systemPromptOptions.selectedTools ?? [];
    if (activas.includes("buscar_web")) {
      event.systemPromptOptions.sections.busqueda_web = POLITICA;
    } else {
      delete event.systemPromptOptions.sections.busqueda_web;
    }
  });
}
