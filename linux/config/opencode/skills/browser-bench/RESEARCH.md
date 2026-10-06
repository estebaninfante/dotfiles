# FASE 0 — Investigación (estado sep-2026)

Host: Brave real en `~/.config/BraveSoftware/Brave-Browser/Default` (perfil con extensiones).
`brave` + `chromium` en PATH. Node 26, npm 11, pnpm 12, bun 1.4, go 1.27, python 3.14 (sin pip/uv).
Wayland (`wayland-1`). OpenCode MCP existente: `supabase`. Agents en `~/.config/opencode/agents/`.

| Herramienta | Tipo | Perfil real Brave (Linux) | Velocidad / tokens | OpenCode | Riesgo / notas | URL |
|---|---|---|---|---|---|---|
| @opencode-ai/browser-control | MCP + CLI + skill | Sí — extension + relay local, perfil logueado | Bueno (Playwright + JS persistente/sesión) | Oficial: `command:["browser-control-mcp"]` | Cargar extension unpacked a mano; Node 22.19+ | npm `@opencode-ai/browser-control` |
| vercel-labs/agent-browser | CLI (Rust) + MCP | Sí — `--profile Default` copia perfil a temp read-only | Top — snapshot `@eN`, delta, batch, `--if-changed` | MCP stdio `["mcp"]`, tools tipados | Instalación pesada; copia perfil = cookies a temp | github.com/vercel-labs/agent-browser |
| brave-mcp (triuzzi/brave-devtools-mcp) | MCP + CLI | Sí — attach Brave real (perfil dedicado o autoConnect) | Medio — 29 tools, ~3.3k tokens contexto | Config OpenCode dada | Privacy: expone contenido al MCP; 28★ | github.com/triuzzi/brave-devtools-mcp |
| browser-use | Lib Python (+CLI MCP) | Sí — `user_data_dir`, `storage_state`, `from_system_chrome`, CDP | Lento/caro: cada paso usa LLM | MCP CLI | ~100k★, mantenido; para autónomo, no low-token | github.com/browser-use/browser-use |
| Browser MCP by Agent360 | MCP + extension | Sí — Chrome/Brave logueado, real mouse events | Medio; 34 tools | MCP estándar | Funciona donde headless muere; 36★ activo jul-2026 | github.com/Agent360dk/browser-mcp |
| OpenBrowser (openbrowser-ai) | MCP + CLI | CDP perfil real | Muy bajo — un `execute_code`, bench 6x menos tokens | MCP stdio | MIT; hosted waitlist | openbrowser.me / PyPI `openbrowser-ai` |
| auto-browser (LvcidPsyche) | MCP-native + Docker | Playwright perfil propio + auth profiles | Medio | HTTP/stdio MCP | 795★; human-in-the-loop noVNC | github.com/LvcidPsyche/auto-browser |
| Fast Browser MCP (kqlio67) | MCP CDP | CDP Chrome/Chromium | Alto — `browser_batch` + `@ref` <150 tok | MCP | 0★ (riesgo mantenimiento) | mcpmarket.com/server/fast-browser |
| Stagehand + Browserbase | SDK TS/Py/Go | Local Chrome o cloud | Medio; act/observe/extract self-healing | SDK, MCP cloud | Cloud opcional; no perfil Brave directo | github.com/browserbase/stagehand |
| Playwright MCP (Microsoft) | MCP baseline | Opcional (CDP/extension) | Bajo (snapshot a11y ~1.5k tok) | MCP estándar | 4.7M desc/sem; headless separado | github.com/microsoft/playwright-mcp |
| browsermcp.io (`@browsermcp/mcp`) | MCP + extension | Sí | — | plugin `opencode-browser` | SIN commits desde abr-2025; MV3 worker muere a 30s. Evitar | github.com/browsermcp/mcp |

Nota: `brave-mcp` de `Leeaandrob` es brave *search* API, no browser control. No confundir.

Top candidatos host: (1) @opencode-ai/browser-control, (2) vercel-labs/agent-browser,
(3) brave-mcp, (4) browser-use, (5) auto-browser.
