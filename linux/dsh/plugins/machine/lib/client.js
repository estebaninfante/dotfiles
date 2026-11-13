/**
 * dsh-local-machine — client half.
 *
 * Panel del harness (barra lateral + contenido del centro, no overlay).
 * Copia el lenguaje de la página de Plugins del propio harness: columna
 * centrada de 960px, título 20/500, grupos con conteo, filas planas separadas
 * por un hilo de .5px, menús translúcidos y diálogo con máscara. Nada de
 * tarjetas KPI ni gradientes; el color va en el texto, nunca en puntos.
 *
 * Datos: /machine/* (el plugin host invoca el CLI `machine`).
 */
window.__ModuleLoader__.load({
	id: "dsh-local-machine",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const PANEL_ID = "machine";
		const STYLE_ID = "dsh-machine-style";
		const TRASH_DIR = "~/.local/share/machine/trash/";
		const RETENTION_DAYS = 30;
		const WIPE_WORD = "VACIAR";
		const STATES = ["unclassified", "active", "paused", "done", "archived"];
		const LABEL = {
			unclassified: "sin decidir",
			active: "activo",
			paused: "pausado",
			done: "terminado",
			archived: "archivado",
		};
		const GROUP = {
			unclassified: "Sin decidir",
			active: "Activos",
			paused: "Pausados",
			done: "Terminados",
			archived: "Archivados",
		};
		// Tono por estado: el color va en el texto del control, no en un punto.
		const TONE = {
			unclassified: "plain",
			active: "ok",
			paused: "plain",
			done: "info",
			archived: "quiet",
		};
		const KINDS = ["project", "product", "experiment", "service", "app", "idea"];
		const KIND_LABEL = {
			project: "proyecto",
			product: "producto",
			experiment: "experimento",
			service: "servicio",
			app: "app",
			idea: "idea",
			task: "tarea",
		};
		const SORTS = [
			{ value: "attention", label: "Por estado" },
			{ value: "recent", label: "Más recientes" },
			{ value: "stale", label: "Más olvidados" },
			{ value: "name", label: "Por nombre" },
		];

		const CSS = `
.mr{
  --mr-fg: var(--dsw-alias-label-primary, #eceef2);
  --mr-fg2: var(--dsw-alias-label-secondary, #a3a8b3);
  --mr-fg3: var(--dsw-alias-label-tertiary, #737985);
  --mr-cap: var(--dsw-alias-label-caption, #737985);
  --mr-dim: var(--dsw-alias-label-dimmed, #4a4f59);
  --mr-l1: var(--dsw-alias-border-l1, #ffffff0f);
  --mr-l2: var(--dsw-alias-border-l2, #ffffff1f);
  --mr-l3: var(--dsw-alias-border-l3, #ffffff29);
  --mr-l4: var(--dsw-alias-border-l4, #ffffff33);
  --mr-hover: var(--dsw-alias-interactive-bg-hover, #ffffff14);
  --mr-active: var(--dsw-alias-interactive-bg-active, #ffffff24);
  --mr-card: var(--dsw-alias-settings-card-fill, var(--dsw-alias-bg-layer-2, #1d2027));
  --mr-card-line: var(--dsw-alias-settings-card-stroke, var(--dsw-alias-border-l4, #ffffff33));
  --mr-field: var(--dsw-alias-bg-layer-1, transparent);
  --mr-ok: var(--dsw-alias-state-success-primary, #2fb36b);
  --mr-info: var(--dsw-alias-state-business-primary, #4d6bfe);
  --mr-warn: var(--dsw-alias-state-warn-primary, #e5a00d);
  --mr-bad: var(--dsw-alias-state-error-primary, #f25a5a);
  --mr-r-sm: var(--dsw-radius-sm, 8px);
  --mr-r-md: var(--dsw-radius-md, 12px);
  --mr-r-lg: var(--dsw-radius-lg, 16px);
  --mr-r-xl: var(--dsw-radius-xl, 20px);
  --mr-mono: var(--ds-font-family-code, ui-monospace, SFMono-Regular, Menlo, monospace);
  --mr-ring: var(--dsw-focus-ring-width, 2px) solid var(--dsw-focus-ring-color, var(--mr-info));
  box-sizing:border-box;height:100%;min-height:0;overflow:auto;color:var(--mr-fg);
  display:flex;flex-direction:column;align-items:center;gap:28px;
  padding:0 clamp(24px,4vw,48px) 48px;font-size:13px;line-height:20px;
}
.mr *,.mr-layer *{box-sizing:border-box}
.mr>*{width:100%;max-width:960px}
.mr>.mr-layer{max-width:none}
:where(.mr) button{font:inherit}
.mr :focus-visible,.mr-layer :focus-visible{outline:var(--mr-ring);outline-offset:1px}

/* --- Cabecera ------------------------------------------------------------ */
.mr-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding-top:28px}
[data-platform=darwin] .mr-head{padding-top:calc(28px + var(--dsh-frame-top-clearance,0px))}
.mr-h1{margin:0;font-size:20px;font-weight:500;line-height:28px}
.mr-intro{margin:4px 0 0;font-size:13px;line-height:20px;color:var(--mr-fg2);display:flex;flex-wrap:wrap;gap:0 6px}
.mr-intro b{font-weight:500;color:var(--mr-fg);font-variant-numeric:tabular-nums}
.mr-intro [data-warn="1"] b{color:var(--mr-warn)}
.mr-intro i{font-style:normal;color:var(--mr-cap)}
.mr-toolbar{display:flex;align-items:center;gap:8px;flex:none}
.mr-search{display:inline-flex;align-items:center;gap:6px;height:32px;width:220px;padding:0 10px;
  border:.5px solid var(--mr-l4);border-radius:var(--mr-r-md);background:var(--mr-field)}
.mr-search:focus-within{border-color:var(--mr-info)}
.mr-search svg{flex:none;color:var(--mr-fg3)}
.mr-search input{flex:1;min-width:0;border:0;outline:0;background:transparent;color:var(--mr-fg);
  font:inherit;font-size:13px;line-height:20px}
.mr-search input::placeholder{color:var(--mr-fg3)}
.mr-search kbd{font:inherit;font-size:11px;color:var(--mr-cap)}

/* --- Botones (mismas medidas que Button sm/md del harness) --------------- */
.mr-btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;height:32px;padding:0 12px;
  border:.5px solid var(--mr-l4);border-radius:var(--mr-r-md);background:transparent;color:var(--mr-fg);
  font-size:13px;line-height:20px;cursor:pointer;white-space:nowrap}
.mr-btn:hover:not(:disabled){background:var(--mr-hover)}
.mr-btn:active:not(:disabled){background:var(--mr-active)}
.mr-btn:disabled{opacity:.4;cursor:default}
.mr-btn[data-size=sm]{height:28px;padding:0 10px;font-size:12px;line-height:18px;border-radius:var(--mr-r-sm)}
.mr-btn[data-variant=ghost]{border-color:transparent;color:var(--mr-fg2)}
.mr-btn[data-variant=ghost]:hover:not(:disabled){color:var(--mr-fg)}
.mr-btn[data-variant=danger]{color:var(--mr-bad);border-color:color-mix(in srgb,var(--mr-bad) 30%,transparent)}
.mr-btn[data-variant=danger]:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover-danger,color-mix(in srgb,var(--mr-bad) 10%,transparent))}
.mr-btn[data-variant=solid-danger]{border-color:transparent;background:var(--mr-bad);color:#fff;font-weight:500}
.mr-btn[data-variant=solid-danger]:hover:not(:disabled){background:color-mix(in srgb,var(--mr-bad) 88%,#000)}
.mr-icon{display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;flex:none;padding:0;
  border:0;border-radius:var(--mr-r-sm);background:transparent;color:var(--mr-cap);cursor:pointer}
.mr-icon:hover:not(:disabled){background:var(--mr-hover);color:var(--mr-fg2)}
.mr-icon[data-danger="1"]:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover-danger,var(--mr-hover));color:var(--mr-bad)}
.mr-icon:disabled{opacity:.4;cursor:default}

/* --- Avisos --------------------------------------------------------------- */
.mr-note{display:flex;align-items:flex-start;gap:10px;margin:0;padding:8px 12px;border-radius:var(--mr-r-md);
  font-size:13px;line-height:20px;color:var(--mr-fg)}
.mr-note[data-tone=ok]{background:color-mix(in srgb,var(--mr-ok) 10%,transparent)}
.mr-note[data-tone=bad]{background:color-mix(in srgb,var(--mr-bad) 10%,transparent)}
.mr-note[data-tone=warn]{background:var(--dsw-alias-state-warn-tertiary,color-mix(in srgb,var(--mr-warn) 12%,transparent))}
.mr-note span{flex:1;min-width:0;overflow-wrap:anywhere}
.mr-note button{flex:none;margin:-4px -6px -4px 0}

/* --- Filtros: Pill del harness ------------------------------------------- */
.mr-bar{display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:-12px}
.mr-pill{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;border:0;border-radius:999px;
  background:transparent;color:var(--mr-fg2);font-size:12.5px;line-height:18px;cursor:pointer}
.mr-pill:hover{background:var(--mr-hover);color:var(--mr-fg)}
.mr-pill[aria-pressed=true]{color:var(--mr-fg);font-weight:500;
  background:var(--dsw-alias-button-ghost-active-fill,var(--mr-hover));
  box-shadow:inset 0 0 0 .5px var(--dsw-alias-button-ghost-active-border,var(--mr-l3))}
.mr-pill .n{font-size:11.5px;font-weight:400;color:var(--mr-cap);font-variant-numeric:tabular-nums}
.mr-pill[data-empty="1"]{color:var(--mr-fg3)}
.mr-bar .mr-spacer{flex:1}

/* --- Lista: filas planas como las de Plugins ------------------------------ */
.mr-groups{display:flex;flex-direction:column;gap:28px}
.mr-group{display:flex;flex-direction:column;gap:6px}
.mr-group-head{display:flex;align-items:baseline;gap:8px;margin:0;font-size:14px;font-weight:500;line-height:22px}
.mr-group-head .n{font-size:14px;font-weight:400;color:var(--mr-cap);font-variant-numeric:tabular-nums}
.mr-group-head .hint{margin-left:auto;font-size:12px;font-weight:400;color:var(--mr-fg3)}
.mr-rows{display:flex;flex-direction:column;margin:0 -10px;padding:0;list-style:none}
.mr-row[data-trash]{grid-template-columns:minmax(0,1fr) 96px auto;cursor:default}
.mr-trash-actions{display:flex;gap:6px;justify-content:flex-end}
.mr-count{display:inline-block;margin-left:7px;padding:0 6px;border-radius:99px;background:var(--mr-l3);
  font-size:11px;line-height:17px;color:var(--mr-fg2);font-variant-numeric:tabular-nums}
.mr-row{position:relative;display:grid;align-items:center;gap:12px;min-height:52px;padding:7px 10px;
  grid-template-columns:minmax(0,1fr) 84px 112px 132px 116px 28px;
  border-radius:var(--mr-r-md);cursor:pointer}
.mr-row::after{content:"";position:absolute;left:10px;right:10px;bottom:0;height:.5px;background:var(--mr-l2)}
.mr-row:last-child::after,.mr-row:hover::after,.mr-row:has(+ .mr-row:hover)::after{display:none}
.mr-row:hover,.mr-row[data-open="1"]{background:var(--mr-hover)}
.mr-row:focus-visible{outline:var(--mr-ring);outline-offset:-2px}
.mr-who{display:flex;flex-direction:column;min-width:0}
.mr-name{font-size:13.5px;font-weight:500;line-height:20px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mr-slug{margin-left:7px;font-size:11.5px;font-weight:400;color:var(--mr-fg3)}
.mr-dtitle h1{cursor:text}
.mr-rename{height:32px;font-size:15px;font-weight:600;max-width:420px}
.mr-sub{font-size:12px;line-height:18px;color:var(--mr-fg3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mr-cell{font-size:12.5px;line-height:18px;color:var(--mr-fg2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;
  font-variant-numeric:tabular-nums}
.mr-cell[data-tone=warn]{color:var(--mr-warn)}
.mr-cell[data-tone=quiet]{color:var(--mr-fg3)}
.mr-cell svg{vertical-align:-2px;margin-right:5px}
.mr-row .mr-icon{opacity:0;transition:opacity .12s}
.mr-row:hover .mr-icon,.mr-row:focus-within .mr-icon{opacity:1}
.mr-empty{margin:0;padding:28px 0;color:var(--mr-fg3);font-size:13px;line-height:20px}

/* Esqueleto mientras carga (mismo pulso que Plugins) */
.mr-sk{display:block;height:12px;border-radius:var(--dsw-radius-xs,4px);background:var(--dsw-alias-bg-skeleton,#ffffff14);
  animation:mr-pulse 2s cubic-bezier(.36,0,.64,1) infinite}
@keyframes mr-pulse{0%{opacity:1}40%{opacity:.6}80%,to{opacity:1}}

/* --- Control de estado (Tag del harness, desplegable) ---------------------- */
.mr-tag{display:inline-flex;align-items:center;gap:4px;height:24px;max-width:100%;padding:0 6px 0 9px;
  border:0;border-radius:999px;background:transparent;font-size:12px;line-height:18px;font-weight:500;
  color:var(--mr-fg2);cursor:pointer;white-space:nowrap;box-shadow:inset 0 0 0 .5px var(--mr-l4)}
.mr-tag[data-tone=ok]{color:var(--mr-ok);box-shadow:none;background:color-mix(in srgb,var(--mr-ok) 10%,transparent)}
.mr-tag[data-tone=info]{color:var(--mr-info);box-shadow:none;background:color-mix(in srgb,var(--mr-info) 10%,transparent)}
.mr-tag[data-tone=warn]{color:var(--mr-warn);box-shadow:none;background:color-mix(in srgb,var(--mr-warn) 12%,transparent)}
.mr-tag[data-tone=quiet]{color:var(--mr-fg3)}
.mr-tag:hover{filter:brightness(1.18)}
.mr-tag[data-plain="1"]{padding:0 6px 0 8px;box-shadow:none;color:var(--mr-fg2);font-weight:400}
.mr-tag[data-plain="1"]:hover{filter:none;background:var(--mr-hover);color:var(--mr-fg)}
.mr-chev{flex:none;opacity:.7;transition:transform .16s}
.mr-tag[aria-expanded=true] .mr-chev{transform:rotate(180deg)}

/* --- Menú (Menu + MenuSurface del harness) -------------------------------- */
.mr-menu{position:fixed;z-index:1100;display:flex;flex-direction:column;gap:0;padding:4px;min-width:168px;
  border-radius:var(--mr-r-lg);isolation:isolate;color:var(--mr-fg);font-size:13px;line-height:20px;
  --dsw-elevation-stroke-color:var(--mr-l1);
  box-shadow:var(--dsw-elevation-prominent,0 0 0 .5px var(--mr-l1),0 3px 8px #0000000a,0 0 20px #0000000d);
  animation:mr-fade .12s ease-out}
.mr-menu::before{content:"";position:absolute;inset:0;z-index:-1;border-radius:inherit;
  background:var(--dsw-menu-surface-fill,#2a2c31f2);backdrop-filter:var(--dsw-menu-backdrop-filter,blur(40px) saturate(150%))}
.mr-menu-label{padding:5px 8px 3px;font-size:11px;line-height:16px;color:var(--mr-fg3)}
.mr-menu button{display:flex;align-items:center;gap:8px;width:100%;min-height:30px;padding:4px 8px;border:0;
  border-radius:var(--mr-r-md);background:transparent;color:var(--mr-fg);font-size:13px;line-height:20px;
  text-align:left;cursor:pointer}
.mr-menu button[data-focus="1"]:not(:disabled){background:var(--mr-hover)}
.mr-menu button:disabled{opacity:.4;cursor:not-allowed}
.mr-menu button[data-tone=ok] .t{color:var(--mr-ok)}
.mr-menu button[data-tone=info] .t{color:var(--mr-info)}
.mr-menu button[data-tone=warn] .t{color:var(--mr-warn)}
.mr-menu button[data-tone=quiet] .t{color:var(--mr-fg2)}
.mr-menu .hint{margin-left:auto;padding-left:12px;font-size:11.5px;color:var(--mr-fg3)}
.mr-menu .check{margin-left:auto;padding-left:12px;color:var(--mr-fg2);visibility:hidden}
.mr-menu .hint + .check{margin-left:0}
.mr-menu button[aria-selected=true] .check{visibility:visible}
@keyframes mr-fade{from{opacity:0;transform:translateY(-2px)}to{opacity:1;transform:none}}

/* --- Ficha ---------------------------------------------------------------- */
.mr-detail{display:flex;flex-direction:column;gap:32px;padding-top:28px}
[data-platform=darwin] .mr-detail{padding-top:calc(28px + var(--dsh-frame-top-clearance,0px))}
.mr-crumb{align-self:flex-start;display:inline-flex;align-items:center;gap:6px;padding:0;border:0;background:transparent;
  color:var(--mr-fg3);font-size:12.5px;line-height:18px;cursor:pointer}
.mr-crumb:hover{color:var(--mr-fg)}
.mr-dhead{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-top:-12px}
.mr-dmain{display:flex;flex-direction:column;gap:6px;min-width:0}
.mr-dtitle{display:flex;align-items:center;flex-wrap:wrap;gap:8px;min-width:0}
.mr-dtitle h1{margin:0;font-size:20px;font-weight:500;line-height:28px;overflow-wrap:anywhere}
.mr-ddesc{margin:0;font-size:14px;line-height:22px;color:var(--mr-fg2)}
.mr-dpath{margin:0;font-family:var(--mr-mono);font-size:12px;line-height:18px;color:var(--mr-fg3);overflow-wrap:anywhere}
.mr-dactions{display:flex;align-items:center;gap:8px;flex:none}
.mr-section{display:flex;flex-direction:column;gap:12px}
.mr-section-head{display:flex;align-items:baseline;gap:10px;margin:0;font-size:14px;font-weight:500;line-height:20px}
.mr-section-head .n{font-size:12px;font-weight:400;color:var(--mr-fg2)}
.mr-section-head .aside{margin-left:auto;font-size:12px;font-weight:400;color:var(--mr-fg3)}
.mr-card{display:flex;flex-direction:column;min-width:0;overflow:hidden;
  border:.5px solid var(--mr-card-line);border-radius:var(--mr-r-xl);background:var(--mr-card)}
.mr-kv{display:flex;align-items:center;justify-content:space-between;gap:16px;min-height:48px;padding:10px 16px}
.mr-kv + .mr-kv{border-top:.5px solid var(--mr-l2)}
.mr-kv dt{flex:none;font-size:13px;line-height:20px;color:var(--mr-fg2)}
.mr-kv dd{margin:0;min-width:0;text-align:right;font-size:13px;line-height:20px;color:var(--mr-fg);
  overflow-wrap:anywhere;font-variant-numeric:tabular-nums}
.mr-kv dd[data-tone=warn]{color:var(--mr-warn)}
.mr-kv dd[data-tone=quiet]{color:var(--mr-fg3)}
.mr-kv dd small{display:block;font-size:12px;line-height:18px;color:var(--mr-fg3)}
.mr-kv a{color:var(--mr-fg);text-decoration:underline;text-decoration-color:var(--mr-l4);text-underline-offset:3px}
.mr-kv a:hover{text-decoration-color:currentColor}
.mr-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
.mr-field{width:100%;padding:10px 14px;border:.5px solid var(--mr-l4);border-radius:var(--mr-r-md);
  background:var(--mr-field);color:var(--mr-fg);font:inherit;font-size:13px;line-height:20px;outline:none}
.mr-field:focus{border-color:var(--mr-info);box-shadow:inset 0 0 0 .5px var(--mr-info)}
.mr-field::placeholder{color:var(--mr-fg3)}
textarea.mr-field{min-height:96px;resize:vertical;display:block}
input.mr-field{height:36px;padding:0 12px}
.mr-tasks{display:flex;flex-direction:column;margin:0;padding:0;list-style:none}
.mr-tasks li{display:flex;align-items:flex-start;gap:10px;padding:10px 16px;font-size:13px;line-height:20px}
.mr-tasks li + li{border-top:.5px solid var(--mr-l2)}
.mr-tasks li[data-done="1"] span{color:var(--mr-fg3);text-decoration:line-through}
.mr-tasks input{flex:none;width:16px;height:16px;margin:2px 0 0;accent-color:var(--dsw-alias-brand-primary,var(--mr-info))}
.mr-tasks .mr-empty{padding:12px 16px}
.mr-add{display:flex;gap:8px}
.mr-add .mr-field{flex:1;min-width:0}

/* --- Diálogo de borrado (Modal + RiskConfirmation del harness) ------------ */
.mr-layer{position:fixed;inset:0;z-index:1000;display:flex;align-items:center;justify-content:center;
  padding:max(24px,var(--dsh-frame-overlay-top,24px)) 24px;color:var(--mr-fg);font-size:13px;line-height:20px}
.mr-mask{position:absolute;inset:var(--dsh-frame-chrome-top,0px) 0 0;backdrop-filter:var(--dsw-mask-blur,none);
  background:var(--dsw-alias-bg-mask-1,#00000080);animation:mr-fade .16s ease-out}
.mr-dialog{position:relative;z-index:1;display:flex;flex-direction:column;gap:20px;width:min(460px,100%);max-height:100%;
  padding:0 0 24px;overflow:hidden;border-radius:var(--dsw-radius-panel,28px);background:var(--dsw-alias-bg-layer-2,#1d2027);
  --dsw-elevation-stroke-color:var(--mr-l1);
  box-shadow:var(--dsw-elevation-prominent,0 0 0 .5px var(--mr-l1),0 3px 8px #0000000a,0 0 20px #0000000d);
  animation:mr-fade .16s ease-out}
.mr-dialog header{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:22px 14px 0 24px}
.mr-dialog h2{margin:0;font-size:16px;font-weight:500;line-height:24px;overflow-wrap:anywhere}
.mr-dialog-body{display:flex;flex-direction:column;gap:16px;min-height:0;overflow-y:auto;padding:0 24px;overscroll-behavior:contain}
.mr-dialog-body p{margin:0;font-size:14px;line-height:22px;color:var(--mr-fg2)}
.mr-dialog-body code{font-family:var(--mr-mono);font-size:12px;color:var(--mr-fg)}
.mr-risks{display:flex;flex-direction:column;gap:6px;margin:0;padding:10px 12px;list-style:none;border-radius:var(--mr-r-md);
  background:var(--dsw-alias-state-warn-tertiary,color-mix(in srgb,var(--mr-warn) 12%,transparent))}
.mr-risks[data-tone=ok]{background:color-mix(in srgb,var(--mr-ok) 10%,transparent)}
.mr-risks[data-tone=bad]{background:color-mix(in srgb,var(--mr-bad) 10%,transparent)}
.mr-risks li{display:flex;gap:8px;font-size:12.5px;line-height:18px;color:var(--mr-fg)}
.mr-risks li svg{flex:none;margin-top:1px;color:var(--mr-warn)}
.mr-risks[data-tone=ok] li svg{color:var(--mr-ok)}
.mr-risks[data-tone=bad] li svg{color:var(--mr-bad)}
.mr-risks small{display:block;color:var(--mr-fg2)}
.mr-confirm{display:flex;flex-direction:column;gap:6px;font-size:13px;line-height:20px;color:var(--mr-fg2)}
.mr-confirm b{font-family:var(--mr-mono);font-weight:500;font-size:12.5px;color:var(--mr-fg)}
.mr-confirm .mr-field{height:40px;padding:0 14px;font-family:var(--mr-mono);font-size:13px;background:var(--dsw-alias-bg-layer-3,var(--mr-field))}
.mr-check{display:flex;align-items:flex-start;gap:10px;padding:12px 14px;border:1px solid var(--mr-card-line);
  border-radius:var(--mr-r-md,10px);background:color-mix(in srgb,var(--mr-bad) 4%,transparent);cursor:pointer}
.mr-check[data-disabled="1"]{cursor:default;background:var(--mr-l1);border-color:var(--mr-l3)}
.mr-check input{margin:3px 0 0;accent-color:var(--mr-bad);flex:none}
.mr-check .mr-check-text{display:flex;flex-direction:column;gap:3px;font-size:13px;line-height:19px;min-width:0}
.mr-check code{font-family:var(--mr-mono);font-size:12.5px;word-break:break-all}
.mr-check small{font-size:11.5px;line-height:16px;color:var(--mr-fg3)}
.mr-check small[data-tone="bad"]{color:var(--mr-bad)}
.mr-reason{margin:0;font-size:12px;line-height:18px;color:var(--mr-bad);white-space:pre-wrap;overflow-wrap:anywhere}
.mr-dialog footer{display:flex;align-items:center;justify-content:flex-end;gap:8px;padding:0 24px}

/* --- Celular -------------------------------------------------------------- */
@media (max-width:820px){
  .mr{padding:0 16px 32px;gap:22px}
  .mr-head{flex-direction:column;align-items:stretch;padding-top:18px}
  .mr-search{flex:1;width:auto;min-width:0;height:40px}
  .mr-search input{width:0}
  .mr-search input,.mr-field,.mr-confirm .mr-field{font-size:16px}
  .mr-search kbd{display:none}
  .mr-btn{height:40px}
  .mr-pill{height:36px}
  .mr-row{grid-template-columns:minmax(0,1fr) auto;min-height:60px;touch-action:manipulation}
  .mr-row > .mr-cell,.mr-row > .mr-icon{display:none}
  .mr-tag{height:32px}
  .mr-detail{padding-top:18px}
  .mr-dhead{flex-direction:column;align-items:stretch}
  .mr-grid{grid-template-columns:minmax(0,1fr)}
  .mr-menu button{min-height:40px}
}
`;

		/* ------------------------------------------------------------------ */
		/* Utilidades                                                          */
		/* ------------------------------------------------------------------ */

		async function api(path, body) {
			const options = body
				? {
						method: "POST",
						headers: { "content-type": "application/json", "x-dsh-machine": "1" },
						body: JSON.stringify(body),
					}
				: { method: "GET" };
			const res = await fetch(path, options);
			const data = await res.json().catch(() => ({}));
			if (!res.ok) {
				const error = new Error(data.message || data.error || `HTTP ${res.status}`);
				error.status = res.status;
				throw error;
			}
			return data;
		}

		function useStyles() {
			React.useEffect(() => {
				let style = document.getElementById(STYLE_ID);
				if (!style) {
					style = document.createElement("style");
					style.id = STYLE_ID;
					document.head.appendChild(style);
				}
				// Siempre se reescribe: al refrescar el chunk el CSS nuevo pisa al viejo.
				if (style.textContent !== CSS) style.textContent = CSS;
			}, []);
		}

		function ageLabel(days) {
			if (days == null) return "—";
			if (days === 0) return "hoy";
			if (days === 1) return "ayer";
			if (days < 30) return `hace ${days} d`;
			const months = Math.floor(days / 30);
			if (months < 12) return months === 1 ? "hace 1 mes" : `hace ${months} meses`;
			const years = Math.floor(days / 365);
			return years <= 1 ? "hace 1 año" : `hace ${years} años`;
		}

		function shortTitle(p) {
			const t = (p.title || "").trim();
			if (!t) return "";
			if (t.toLowerCase() === p.slug.toLowerCase()) return "";
			const clean = t.replace(/^AGENTS\.md\s*—\s*/i, "").replace(/^#\s*/, "");
			return clean.toLowerCase() === p.slug.toLowerCase() ? "" : clean;
		}

		function plural(n, one, many) {
			return `${n} ${n === 1 ? one : many}`;
		}

		/** `https://github.com/owner/name.git` -> `owner/name`. */
		function ghRepoSlug(url) {
			const value = String(url || "");
			if (!value.includes("github.com")) return "";
			let tail = value.split("github.com").pop().replace(/^[:/]+/, "");
			tail = tail.replace(/\.git$/, "").replace(/\/+$/, "");
			return tail.split("/").length === 2 ? tail : "";
		}

		/** Lo que se pierde (o impide) mandar un proyecto a la papelera. */
		function trashRisks(p) {
			const f = p.facts || {};
			const dirty = Number(f.dirty || 0);
			const ahead = String(f.ahead ?? "0");
			const path = f.path || "";
			const parent = path.replace(/\/+$/, "").split("/").slice(-2, -1)[0];
			const blockers = [];
			const losses = [];
			if (!path) blockers.push(["No tiene carpeta registrada", "No hay nada que mover; correr Actualizar."]);
			else if (parent !== "Proyectos")
				blockers.push(["La carpeta no está directamente en ~/Proyectos", "Por seguridad solo se mueven carpetas de ahí."]);
			const liveUnits = String(f.systemd_active || "").split(",").filter(Boolean);
			if (liveUnits.length)
				blockers.push([
					"Tiene un servicio corriendo",
					`${liveUnits.join(", ")} · deshabilitalo acá abajo y seguí.`,
				]);
			if (dirty > 0) losses.push([plural(dirty, "archivo sin guardar", "archivos sin guardar"), "Cambios que nunca entraron en un commit."]);
			if (ahead === "?" && f.remote_url) losses.push(["La rama no tiene copia remota", "Ningún commit de esta rama está subido."]);
			else if (ahead !== "0" && Number(ahead) > 0)
				losses.push([plural(Number(ahead), "commit sin subir", "commits sin subir"), "Solo existen en esta máquina."]);
			if (!f.remote_url) losses.push(["Sin remoto", "No hay copia en GitHub ni en ningún otro lado."]);
			return { blockers, losses };
		}

		/* ------------------------------------------------------------------ */
		/* Iconos (16px, trazo 1.3 como los del harness)                       */
		/* ------------------------------------------------------------------ */

		function svg(size, children, extra) {
			return h(
				"svg",
				Object.assign(
					{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
					extra || {},
				),
				...children,
			);
		}
		const stroke = { stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round", strokeLinejoin: "round" };

		function IconSearch() {
			return svg(14, [
				h("circle", Object.assign({ key: 1, cx: 7, cy: 7, r: 4.5 }, stroke)),
				h("path", Object.assign({ key: 2, d: "M10.4 10.4 13.5 13.5" }, stroke)),
			]);
		}
		function IconChevron(props) {
			return svg(
				props && props.size ? props.size : 12,
				[h("path", Object.assign({ key: 1, d: "M4.5 6.5 8 10l3.5-3.5" }, stroke))],
				{ className: "mr-chev" },
			);
		}
		function IconBack() {
			return svg(14, [h("path", Object.assign({ key: 1, d: "M9.5 4 5.5 8l4 4" }, stroke))]);
		}
		function IconTrash() {
			return svg(16, [
				h("path", Object.assign({ key: 1, d: "M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.1c.05.8.7 1.4 1.5 1.4h2.8c.8 0 1.45-.6 1.5-1.4l.6-8.1" }, stroke)),
				h("path", Object.assign({ key: 2, d: "M6.8 7.2v4M9.2 7.2v4" }, stroke)),
			]);
		}
		function IconClose() {
			return svg(16, [h("path", Object.assign({ key: 1, d: "M4.5 4.5l7 7M11.5 4.5l-7 7" }, stroke))]);
		}
		function IconFolder() {
			return svg(14, [
				h("path", Object.assign({ key: 1, d: "M2 4.5c0-.8.7-1.5 1.5-1.5h2.6l1.5 1.5h4.9c.8 0 1.5.7 1.5 1.5v5.5c0 .8-.7 1.5-1.5 1.5h-9c-.8 0-1.5-.7-1.5-1.5v-7Z" }, stroke)),
			]);
		}
		function IconAlert() {
			return svg(14, [
				h("path", Object.assign({ key: 1, d: "M8 2.2 14.3 13H1.7L8 2.2Z" }, stroke)),
				h("path", Object.assign({ key: 2, d: "M8 6.5v3M8 11.3v.1" }, stroke)),
			]);
		}
		function IconCheck() {
			return svg(14, [h("path", Object.assign({ key: 1, d: "M3.5 8.3 6.5 11l6-6.5" }, stroke))]);
		}
		function IconBlock() {
			return svg(14, [
				h("circle", Object.assign({ key: 1, cx: 8, cy: 8, r: 5.5 }, stroke)),
				h("path", Object.assign({ key: 2, d: "M4.2 11.8l7.6-7.6" }, stroke)),
			]);
		}
		function IconGithub() {
			return h(
				"svg",
				{ width: 12, height: 12, viewBox: "0 0 16 16", fill: "currentColor", "aria-hidden": "true" },
				h("path", {
					d:
						"M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38v-1.34c-2.22.48-2.69-1.07-2.69-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.05-.49.05-.49.81.06 1.23.83 1.23.83.72 1.23 1.88.87 2.34.67.07-.52.28-.87.5-1.07-1.77-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.03 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.28.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 0 0 8 0Z",
				}),
			);
		}

		/* ------------------------------------------------------------------ */
		/* Menú desplegable propio (estado, tipo, orden). Nada de <select>.     */
		/* ------------------------------------------------------------------ */

		/**
		 * props: value, options [{value,label,tone?,hint?,disabled?}], onChange,
		 * title, label? (encabezado del menú), plain? (sin tono), align? ("end").
		 */
		function Dropdown(props) {
			const { value, options, onChange } = props;
			const [open, setOpen] = React.useState(false);
			const [pos, setPos] = React.useState(null);
			const [focus, setFocus] = React.useState(0);
			const triggerRef = React.useRef(null);
			const menuRef = React.useRef(null);
			const current = options.find((o) => o.value === value) || { value, label: String(value) };

			const step = React.useCallback(
				(from, dir) => {
					for (let i = 1; i <= options.length; i += 1) {
						const next = (from + dir * i + options.length) % options.length;
						if (!options[next].disabled) return next;
					}
					return from;
				},
				[options],
			);

			const openMenu = React.useCallback(() => {
				const el = triggerRef.current;
				if (!el) return;
				const rect = el.getBoundingClientRect();
				const rowH = window.matchMedia && window.matchMedia("(max-width:820px)").matches ? 40 : 30;
				const height = options.length * rowH + 8 + (props.label ? 24 : 0);
				const width = Math.max(176, rect.width);
				const below = rect.bottom + 4;
				const top = below + height > window.innerHeight - 8 ? rect.top - height - 4 : below;
				const left = props.align === "end" ? rect.right - width : rect.left;
				setPos({
					top: Math.max(8, top),
					left: Math.max(8, Math.min(left, window.innerWidth - width - 8)),
					width,
				});
				const at = options.findIndex((o) => o.value === value);
				setFocus(at >= 0 ? at : step(-1, 1));
				setOpen(true);
			}, [options, value, props.align, props.label, step]);

			const pick = React.useCallback(
				(option) => {
					setOpen(false);
					if (option.disabled || option.value === value) return;
					onChange(option.value);
				},
				[onChange, value],
			);

			React.useEffect(() => {
				if (!open) return;
				const onDown = (event) => {
					if (menuRef.current && menuRef.current.contains(event.target)) return;
					if (triggerRef.current && triggerRef.current.contains(event.target)) return;
					setOpen(false);
				};
				const onKey = (event) => {
					if (event.key === "Escape") {
						event.preventDefault();
						event.stopPropagation();
						setOpen(false);
						triggerRef.current && triggerRef.current.focus();
					} else if (event.key === "ArrowDown") {
						event.preventDefault();
						setFocus((f) => step(f, 1));
					} else if (event.key === "ArrowUp") {
						event.preventDefault();
						setFocus((f) => step(f, -1));
					} else if (event.key === "Enter" || event.key === " ") {
						event.preventDefault();
						event.stopPropagation();
						pick(options[focus]);
					} else if (event.key === "Tab") {
						setOpen(false);
					}
				};
				const onScroll = (event) => {
					if (menuRef.current && menuRef.current.contains(event.target)) return;
					setOpen(false);
				};
				document.addEventListener("mousedown", onDown);
				document.addEventListener("keydown", onKey, true);
				window.addEventListener("scroll", onScroll, true);
				window.addEventListener("resize", onScroll);
				return () => {
					document.removeEventListener("mousedown", onDown);
					document.removeEventListener("keydown", onKey, true);
					window.removeEventListener("scroll", onScroll, true);
					window.removeEventListener("resize", onScroll);
				};
			}, [open, focus, options, pick, step]);

			const trigger = h(
				"button",
				{
					ref: triggerRef,
					type: "button",
					className: "mr-tag",
					"data-tone": props.plain ? undefined : current.tone,
					"data-plain": props.plain ? 1 : 0,
					"aria-haspopup": "listbox",
					"aria-expanded": open ? "true" : "false",
					title: props.title,
					onClick: (event) => {
						event.stopPropagation();
						if (open) setOpen(false);
						else openMenu();
					},
					onKeyDown: (event) => {
						if (!open && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
							event.preventDefault();
							openMenu();
						}
					},
				},
				h("span", null, props.prefix ? `${props.prefix} ${current.label}` : current.label),
				h(IconChevron),
			);

			if (!open || !pos) return trigger;

			return h(
				React.Fragment,
				null,
				trigger,
				h(
					"div",
					{
						ref: menuRef,
						className: "mr-menu",
						role: "listbox",
						style: { top: pos.top, left: pos.left, width: pos.width },
						onClick: (event) => event.stopPropagation(),
					},
					props.label ? h("div", { className: "mr-menu-label" }, props.label) : null,
					options.map((option, index) =>
						h(
							"button",
							{
								key: option.value,
								type: "button",
								role: "option",
								disabled: option.disabled,
								"aria-selected": option.value === value ? "true" : "false",
								"data-tone": option.tone,
								"data-focus": index === focus ? 1 : 0,
								title: option.disabled ? option.hint : undefined,
								onMouseEnter: () => setFocus(index),
								onClick: () => pick(option),
							},
							h("span", { className: "t" }, option.label),
							option.hint ? h("span", { className: "hint" }, option.hint) : null,
							h("span", { className: "check" }, h(IconCheck)),
						),
					),
				),
			);
		}

		function stateOptions(kind) {
			return STATES.map((s) => {
				const blocked = s === "done" && kind !== "project" && kind !== "experiment";
				return {
					value: s,
					label: LABEL[s],
					tone: TONE[s],
					disabled: blocked,
					hint: blocked ? (kind === "product" ? "un producto se pausa o archiva" : "solo proyecto o experimento") : undefined,
				};
			});
		}

		function StateControl(props) {
			return h(Dropdown, {
				value: props.value,
				options: stateOptions(props.kind),
				onChange: props.onChange,
				title: "Cambiar estado",
				label: "Estado",
			});
		}

		const KIND_OPTIONS = KINDS.map((k) => ({ value: k, label: KIND_LABEL[k] }));

		/* ------------------------------------------------------------------ */
		/* Diálogo de borrado                                                  */
		/* ------------------------------------------------------------------ */

		function WipeDialog(props) {
			const { count, onCancel, onConfirm } = props;
			const [typed, setTyped] = React.useState("");
			const [busy, setBusy] = React.useState(false);
			const inputRef = React.useRef(null);
			const ready = typed.trim().toUpperCase() === WIPE_WORD;

			React.useEffect(() => {
				const t = setTimeout(() => inputRef.current && inputRef.current.focus(), 30);
				const onKey = (event) => {
					if (event.key !== "Escape") return;
					event.preventDefault();
					event.stopPropagation();
					if (!busy) onCancel();
				};
				document.addEventListener("keydown", onKey, true);
				return () => {
					clearTimeout(t);
					document.removeEventListener("keydown", onKey, true);
				};
			}, [busy, onCancel]);

			return h(
				"div",
				{ className: "mr-layer", role: "presentation" },
				h("div", { className: "mr-mask", onClick: () => !busy && onCancel() }),
				h(
					"div",
					{ className: "mr-dialog", role: "alertdialog", "aria-modal": "true", "aria-labelledby": "mr-wipe-title" },
					h(
						"header",
						null,
						h("h2", { id: "mr-wipe-title" }, "Vaciar la papelera"),
						h("button", { type: "button", className: "mr-icon", onClick: onCancel, disabled: busy, title: "Cancelar (Esc)" }, h(IconClose)),
					),
					h(
						"div",
						{ className: "mr-dialog-body" },
						h(
							"p",
							null,
							`Se van a borrar ${count} proyecto(s) para siempre. No hay vuelta atrás: no queda copia en `,
							h("code", null, TRASH_DIR),
							".",
						),
						h(
							"label",
							{ className: "mr-confirm" },
							h("span", null, "Para confirmar, escribí ", h("b", null, WIPE_WORD)),
							h("input", {
								ref: inputRef,
								className: "mr-field",
								value: typed,
								spellCheck: false,
								autoComplete: "off",
								disabled: busy,
								onChange: (event) => setTyped(event.target.value),
								onKeyDown: (event) => {
									if (event.key === "Enter" && ready) {
										event.preventDefault();
										setBusy(true);
										onConfirm();
									}
								},
							}),
						),
					),
					h(
						"footer",
						null,
						h("button", { type: "button", className: "mr-btn", "data-variant": "ghost", onClick: onCancel, disabled: busy }, "Cancelar"),
						h(
							"button",
							{
								type: "button",
								className: "mr-btn",
								"data-variant": "solid-danger",
								disabled: !ready || busy,
								onClick: () => {
									setBusy(true);
									onConfirm();
								},
							},
							busy ? "Vaciando…" : "Vaciar para siempre",
						),
					),
				),
			);
		}

		function TrashDialog(props) {
			const { onCancel, onDone } = props;
			const [project, setProject] = React.useState(props.project);
			const [disabling, setDisabling] = React.useState(false);
			const [typed, setTyped] = React.useState("");
			const [busy, setBusy] = React.useState(false);
			const [reason, setReason] = React.useState("");
			const [alsoGithub, setAlsoGithub] = React.useState(false);
			const [gh, setGh] = React.useState(null);
			const inputRef = React.useRef(null);
			const { blockers, losses } = trashRisks(project);
			const f = project.facts || {};
			const matches = typed.trim() === project.slug;
			const blocked = blockers.length > 0;
			const repo = f.remote_host === "github" ? ghRepoSlug(f.remote_url) : "";
			const canDeleteRepo = repo.length > 0;
			const ghReady = gh === null ? false : gh.can_delete === true;
			const githubBlocked = alsoGithub && gh !== null && !ghReady;

			React.useEffect(() => {
				if (!canDeleteRepo) return;
				let alive = true;
				api("/machine/gh")
					.then((data) => alive && setGh(data))
					.catch(() => alive && setGh({ can_delete: false }));
				return () => {
					alive = false;
				};
			}, [canDeleteRepo]);

			React.useEffect(() => {
				const t = setTimeout(() => inputRef.current && inputRef.current.focus(), 30);
				const onKey = (event) => {
					if (event.key !== "Escape") return;
					event.preventDefault();
					event.stopPropagation();
					if (!busy) onCancel();
				};
				document.addEventListener("keydown", onKey, true);
				return () => {
					clearTimeout(t);
					document.removeEventListener("keydown", onKey, true);
				};
			}, [busy, onCancel]);

			const submit = async () => {
				if (!matches || blocked || busy || githubBlocked) return;
				setBusy(true);
				setReason("");
				try {
					await api("/machine/trash", { slug: project.slug, github: alsoGithub });
					onDone(project.slug);
				} catch (err) {
					setBusy(false);
					setReason(
						err.status === 404 || err.status === 405
							? "El servidor del harness todavía no tiene la ruta de borrado. Reinicialo (dsh-web --restart) y probá de nuevo."
							: String(err.message || err).replace(/^machine:\s*/, ""),
					);
				}
			};

			const riskList = (tone, items, Icon) =>
				h(
					"ul",
					{ className: "mr-risks", "data-tone": tone },
					items.map(([title, why]) =>
						h("li", { key: title }, h(Icon), h("span", null, title, why ? h("small", null, why) : null)),
					),
				);

			return h(
				"div",
				{ className: "mr-layer", role: "presentation" },
				h("div", { className: "mr-mask", onClick: () => !busy && onCancel() }),
				h(
					"div",
					{
						className: "mr-dialog",
						role: "alertdialog",
						"aria-modal": "true",
						"aria-labelledby": "mr-trash-title",
					},
					h(
						"header",
						null,
						h("h2", { id: "mr-trash-title" }, `Mandar ${project.slug} a la papelera`),
						h(
							"button",
							{ type: "button", className: "mr-icon", onClick: onCancel, disabled: busy, title: "Cancelar (Esc)" },
							h(IconClose),
						),
					),
					h(
						"div",
						{ className: "mr-dialog-body" },
						h(
							"p",
							null,
							"La carpeta no se destruye: se mueve a ",
							h("code", null, `${TRASH_DIR}<fecha>/`),
							" y el proyecto sale de esta lista. Para recuperarlo, movela de vuelta a ",
							h("code", null, "~/Proyectos"),
							" y tocá Actualizar.",
						),
						f.path ? h("p", null, h("code", null, f.path.replace(/^\/home\/[^/]+/, "~"))) : null,
						String((project.facts || {}).systemd_active || "")
							.split(",")
							.filter(Boolean).length
							? h(
									"button",
									{
										type: "button",
										className: "mr-btn",
										"data-variant": "danger",
										disabled: disabling,
										onClick: async () => {
											setDisabling(true);
											try {
												const out = await api("/machine/service-disable", { slug: project.slug });
												if (out.project) setProject(out.project);
											} catch (err) {
												setReason(err.message);
											}
											setDisabling(false);
										},
									},
									disabling ? "Parando…" : "Parar y deshabilitar el servicio",
								)
							: null,
						blocked
							? riskList("bad", blockers, IconBlock)
							: losses.length
								? riskList("warn", losses, IconAlert)
								: riskList("ok", [["Todo está subido al remoto", "No se pierde trabajo."]], IconCheck),
						canDeleteRepo
							? h(
									"label",
									{ className: "mr-check", "data-disabled": !ghReady ? 1 : 0 },
									h("input", {
										type: "checkbox",
										checked: alsoGithub,
										disabled: busy || !ghReady,
										onChange: (event) => setAlsoGithub(event.target.checked),
									}),
									h(
										"span",
										{ className: "mr-check-text" },
										h("span", null, "Borrar también el repositorio en GitHub"),
										h("small", null, h("code", null, repo), " · no se puede deshacer desde acá"),
										ghReady
											? h("small", { "data-tone": "bad" }, "El repo desaparece de GitHub junto con su historial, issues y estrellas.")
											: h(
													"small",
													null,
													gh === null
														? "consultando permisos de gh…"
														: "falta el permiso delete_repo: corré gh auth refresh -s delete_repo",
												),
									),
								)
							: null,
						blocked
							? null
							: h(
									"label",
									{ className: "mr-confirm" },
									h("span", null, "Para confirmar, escribí ", h("b", null, project.slug)),
									h("input", {
										ref: inputRef,
										className: "mr-field",
										value: typed,
										spellCheck: false,
										autoComplete: "off",
										autoCapitalize: "off",
										disabled: busy,
										"aria-invalid": typed && !project.slug.startsWith(typed.trim()) ? "true" : "false",
										onChange: (event) => setTyped(event.target.value),
										onKeyDown: (event) => {
											if (event.key === "Enter") {
												event.preventDefault();
												submit();
											}
										},
									}),
								),
						reason ? h("p", { className: "mr-reason" }, reason) : null,
					),
					h(
						"footer",
						null,
						h("button", { type: "button", className: "mr-btn", "data-variant": "ghost", onClick: onCancel, disabled: busy }, "Cancelar"),
						h(
							"button",
							{
								type: "button",
								className: "mr-btn",
								"data-variant": "solid-danger",
								disabled: !matches || blocked || busy || githubBlocked,
								onClick: submit,
							},
							busy
								? alsoGithub
									? "Borrando en GitHub…"
									: "Moviendo…"
								: alsoGithub
									? "Papelera y GitHub"
									: "Mandar a la papelera",
						),
					),
				),
			);
		}

		/* ------------------------------------------------------------------ */
		/* Panel                                                               */
		/* ------------------------------------------------------------------ */

		function MachinePanel() {
			useStyles();
			const [projects, setProjects] = React.useState([]);
			const [filter, setFilter] = React.useState("all");
			const [sort, setSort] = React.useState("attention");
			const [query, setQuery] = React.useState("");
			const [selected, setSelected] = React.useState(null);
			const [detail, setDetail] = React.useState(null);
			const [error, setError] = React.useState("");
			const [flash, setFlash] = React.useState("");
			const [loading, setLoading] = React.useState(true);
			const [scanning, setScanning] = React.useState(false);
			const [trashing, setTrashing] = React.useState(null);
			const [view, setView] = React.useState("list");
			const [trash, setTrash] = React.useState([]);
			const [wiping, setWiping] = React.useState(false);
			const [trashBusy, setTrashBusy] = React.useState("");
			const [noteState, setNoteState] = React.useState("");
			const [renaming, setRenaming] = React.useState(false);
			const searchRef = React.useRef(null);
			const scrollRef = React.useRef(null);
			const listScroll = React.useRef(0);

			const load = React.useCallback(async () => {
				try {
					const data = await api("/machine/projects");
					setProjects((data.projects || []).filter((p) => p.kind !== "task"));
					setError("");
				} catch (err) {
					setError(err.message);
				} finally {
					setLoading(false);
				}
			}, []);

			React.useEffect(() => {
				load();
			}, [load]);

			const loadTrash = React.useCallback(async () => {
				try {
					const data = await api("/machine/trash");
					setTrash(data.entries || []);
				} catch (err) {
					setError(err.message);
				}
			}, []);

			React.useEffect(() => {
				loadTrash();
			}, [loadTrash]);

			const recover = React.useCallback(
				async (slug) => {
					setTrashBusy(slug);
					try {
						await api("/machine/trash-recover", { slug });
						setFlash(`${slug} volvió a ~/Proyectos.`);
						await Promise.all([loadTrash(), load()]);
					} catch (err) {
						setError(err.message);
					}
					setTrashBusy("");
				},
				[load, loadTrash],
			);

			const wipeOne = React.useCallback(
				async (slug) => {
					setTrashBusy(slug);
					try {
						await api("/machine/trash-delete", { slug });
						setFlash(`${slug} borrado definitivamente.`);
						await loadTrash();
					} catch (err) {
						setError(err.message);
					}
					setTrashBusy("");
				},
				[loadTrash],
			);

			const wipeAll = React.useCallback(async () => {
				setWiping(false);
				try {
					await api("/machine/trash-delete", { all: true });
					setFlash("Papelera vaciada.");
					await loadTrash();
				} catch (err) {
					setError(err.message);
				}
			}, [loadTrash]);

			React.useEffect(() => {
				if (!flash) return;
				const t = setTimeout(() => setFlash(""), 6000);
				return () => clearTimeout(t);
			}, [flash]);

			const rescan = React.useCallback(async () => {
				setScanning(true);
				try {
					await api("/machine/scan", {});
				} catch (err) {
					setError(err.message);
				}
				await load();
				setScanning(false);
			}, [load]);

			const open = React.useCallback(async (slug) => {
				if (scrollRef.current) listScroll.current = scrollRef.current.scrollTop;
				setSelected(slug);
				setDetail(null);
				setNoteState("");
				if (scrollRef.current) scrollRef.current.scrollTop = 0;
				try {
					setDetail(await api(`/machine/project?slug=${encodeURIComponent(slug)}`));
				} catch (err) {
					setError(err.message);
				}
			}, []);

			const refreshDetail = React.useCallback(async (slug) => {
				try {
					setDetail(await api(`/machine/project?slug=${encodeURIComponent(slug)}`));
				} catch (err) {
					setError(err.message);
				}
			}, []);

			const close = React.useCallback(() => {
				setSelected(null);
				setDetail(null);
				requestAnimationFrame(() => {
					if (scrollRef.current) scrollRef.current.scrollTop = listScroll.current;
				});
			}, []);

			const patch = React.useCallback((slug, fields) => {
				setProjects((prev) => prev.map((p) => (p.slug === slug ? Object.assign({}, p, fields) : p)));
				setDetail((prev) => (prev && prev.slug === slug ? Object.assign({}, prev, fields) : prev));
			}, []);

			const changeField = React.useCallback(
				async (slug, field, next) => {
					const before = projects.find((p) => p.slug === slug)?.[field];
					patch(slug, { [field]: next });
					try {
						await api("/machine/entity", { slug, [field]: next });
					} catch (err) {
						setError(err.message);
						patch(slug, { [field]: before });
					}
				},
				[projects, patch],
			);

			const openFolder = React.useCallback(async (path) => {
				try {
					await api("/machine/open", { path });
				} catch (err) {
					setError(err.message);
				}
			}, []);

			const trashed = React.useCallback(
				(slug) => {
					setTrashing(null);
					setProjects((prev) => prev.filter((p) => p.slug !== slug));
					setFlash(`${slug} está en la papelera (${TRASH_DIR}).`);
					if (selected === slug) close();
				},
				[selected, close],
			);

			// Esc vuelve a la lista; "/" enfoca el buscador. Menús y diálogo
			// atrapan su propio Esc antes (captura), así no cierran la ficha.
			React.useEffect(() => {
				const onKey = (event) => {
					if (event.defaultPrevented || trashing) return;
					const tag = (event.target && event.target.tagName) || "";
					const typing = tag === "INPUT" || tag === "TEXTAREA";
					if (event.key === "Escape" && selected && !typing) close();
					if (event.key === "/" && !selected && !typing && searchRef.current) {
						event.preventDefault();
						searchRef.current.focus();
					}
				};
				document.addEventListener("keydown", onKey);
				return () => document.removeEventListener("keydown", onKey);
			}, [selected, trashing, close]);

			const counts = React.useMemo(() => {
				const by = { unclassified: 0, active: 0, paused: 0, done: 0, archived: 0 };
				for (const p of projects) by[p.state] = (by[p.state] || 0) + 1;
				return {
					by,
					total: projects.length,
					stale: projects.filter((p) => p.state !== "archived" && p.age_days != null && p.age_days >= 30).length,
					dirty: projects.filter((p) => Number(p.facts?.dirty || 0) > 0).length,
				};
			}, [projects]);

			const visible = React.useMemo(() => {
				const q = query.trim().toLowerCase();
				let list = projects.filter((p) => filter === "all" || p.state === filter);
				if (q) {
					list = list.filter((p) =>
						[p.slug, p.title, p.note, p.facts?.remote_url].some((v) => (v || "").toLowerCase().includes(q)),
					);
				}
				const age = (p, empty) => (p.age_days == null ? empty : p.age_days);
				return list.slice().sort((a, b) => {
					if (sort === "name") return a.slug.localeCompare(b.slug);
					if (sort === "stale") return age(b, -1) - age(a, -1);
					return age(a, 1e9) - age(b, 1e9) || a.slug.localeCompare(b.slug);
				});
			}, [projects, filter, query, sort]);

			const groups = React.useMemo(() => {
				if (sort !== "attention" || filter !== "all") return [{ key: "flat", rows: visible }];
				return STATES.map((s) => ({ key: s, rows: visible.filter((p) => p.state === s) })).filter(
					(g) => g.rows.length > 0,
				);
			}, [visible, sort, filter]);

			/* --- piezas ---------------------------------------------------- */

			const notices = h(
				React.Fragment,
				null,
				error
					? h(
							"div",
							{ className: "mr-note", "data-tone": "bad", role: "alert" },
							h("span", null, error),
							h("button", { type: "button", className: "mr-icon", onClick: () => setError(""), title: "Cerrar" }, h(IconClose)),
						)
					: null,
				flash
					? h(
							"div",
							{ className: "mr-note", "data-tone": "ok", role: "status" },
							h("span", null, flash),
							h("button", { type: "button", className: "mr-icon", onClick: () => setFlash(""), title: "Cerrar" }, h(IconClose)),
						)
					: null,
			);

			function rowView(p) {
				const f = p.facts || {};
				const dirty = Number(f.dirty || 0);
				const ahead = Number(f.ahead) || 0;
				const host = f.remote_host || "";
				const stale = p.age_days != null && p.age_days >= 30 && p.state !== "archived";
				const tasks = Number(f.tickets_open || 0);
				const summary = (() => {
					const readme = String(f.readme_excerpt || "").trim();
					if (readme) return readme.length > 110 ? readme.slice(0, 107) + "…" : readme;
					const title = shortTitle(p);
					if (title) return title;
					const commit = String(f.last_commit_subject || "").trim();
					if (commit) return `último: ${commit.length > 96 ? commit.slice(0, 93) + "…" : commit}`;
					return "";
				})();
				const sub = [
					summary,
					p.kind && p.kind !== "project" ? KIND_LABEL[p.kind] || p.kind : "",
					f.branch && f.branch !== "main" && f.branch !== "master" ? f.branch : "",
					tasks ? plural(tasks, "tarea abierta", "tareas abiertas") : "",
				].filter(Boolean);
				const alerts = [dirty ? `${dirty} sin guardar` : "", ahead ? `${ahead} sin subir` : ""].filter(Boolean);
				return h(
					"li",
					{
						key: p.slug,
						className: "mr-row",
						tabIndex: 0,
						role: "button",
						"aria-label": `Abrir ${p.slug}`,
						onClick: () => open(p.slug),
						onKeyDown: (event) => {
							if (event.target !== event.currentTarget) return;
							if (event.key === "Enter" || event.key === " ") {
								event.preventDefault();
								open(p.slug);
							}
						},
					},
					h(
						"div",
						{ className: "mr-who" },
						h(
							"span",
							{ className: "mr-name" },
							(p.title && p.title.trim()) || p.slug,
							(p.title && p.title.trim() && p.title.trim() !== p.slug)
								? h("span", { className: "mr-slug" }, p.slug)
								: null,
						),
						h("span", { className: "mr-sub" }, sub.length ? sub.join(" · ") : f.path ? KIND_LABEL[p.kind] || "proyecto" : "sin carpeta"),
					),
					h("span", { className: "mr-cell", "data-tone": stale ? "warn" : undefined, title: f.last_commit ? `último commit ${f.last_commit}` : undefined }, ageLabel(p.age_days)),
					h(
						"span",
						{ className: "mr-cell", "data-tone": host ? undefined : "quiet", title: f.remote_url || "sin remoto" },
						host === "github" ? h(IconGithub) : null,
						host || "sin remoto",
					),
					h(
						"span",
						{ className: "mr-cell", "data-tone": alerts.length ? "warn" : "quiet" },
						alerts.join(" · "),
					),
					h(
						"div",
						{ onClick: (event) => event.stopPropagation() },
						h(StateControl, { value: p.state, kind: p.kind, onChange: (next) => changeField(p.slug, "state", next) }),
					),
					h(
						"button",
						{
							type: "button",
							className: "mr-icon",
							"data-danger": 1,
							title: "Mandar a la papelera…",
							"aria-label": `Mandar ${p.slug} a la papelera`,
							onClick: (event) => {
								event.stopPropagation();
								setTrashing(p);
							},
						},
						h(IconTrash),
					),
				);
			}

			function listView() {
				const intro = [
					h("span", { key: "t" }, h("b", null, String(counts.total)), " proyectos"),
					h("i", { key: "s1" }, "·"),
					h("span", { key: "u" }, h("b", null, String(counts.by.unclassified || 0)), " sin decidir"),
					h("i", { key: "s2" }, "·"),
					h("span", { key: "a" }, h("b", null, `${counts.by.active || 0}/3`), " activos"),
				];
				if (counts.dirty)
					intro.push(
						h("i", { key: "s3" }, "·"),
						h("span", { key: "d", "data-warn": 1 }, h("b", null, String(counts.dirty)), " con cambios sin guardar"),
					);
				if (counts.stale)
					intro.push(
						h("i", { key: "s4" }, "·"),
						h("span", { key: "o" }, h("b", null, String(counts.stale)), " sin tocar hace +30 días"),
					);

				const head = h(
					"header",
					{ className: "mr-head" },
					h("div", null, h("h1", { className: "mr-h1" }, "Proyectos"), h("p", { className: "mr-intro" }, intro)),
					h(
						"div",
						{ className: "mr-toolbar" },
						h(
							"label",
							{ className: "mr-search" },
							h(IconSearch),
							h("input", {
								ref: searchRef,
								placeholder: "Buscar",
								value: query,
								spellCheck: false,
								onChange: (event) => setQuery(event.target.value),
								onKeyDown: (event) => {
									if (event.key === "Escape" && query) {
										event.preventDefault();
										setQuery("");
									}
								},
							}),
							query ? null : h("kbd", null, "/"),
						),
						h(
							"button",
							{
								type: "button",
								className: "mr-btn",
								onClick: rescan,
								disabled: scanning,
								title: "Volver a leer ~/Proyectos del disco",
							},
							scanning ? "Leyendo…" : "Actualizar",
						),
						h(
							"button",
							{
								type: "button",
								className: "mr-btn",
								onClick: () => {
									setView("trash");
									loadTrash();
								},
								title: "Ver la papelera",
							},
							"Papelera",
							trash.length ? h("span", { className: "mr-count" }, String(trash.length)) : null,
						),
					),
				);

				const bar = h(
					"div",
					{ className: "mr-bar", role: "toolbar", "aria-label": "Filtrar por estado" },
					["all", ...STATES].map((s) => {
						const n = s === "all" ? counts.total : counts.by[s] || 0;
						return h(
							"button",
							{
								key: s,
								type: "button",
								className: "mr-pill",
								"aria-pressed": filter === s ? "true" : "false",
								"data-empty": n === 0 ? 1 : 0,
								onClick: () => setFilter(s),
							},
							s === "all" ? "Todos" : GROUP[s],
							h("span", { className: "n" }, String(n)),
						);
					}),
					h("span", { className: "mr-spacer" }),
					h(Dropdown, { value: sort, options: SORTS, onChange: setSort, plain: true, align: "end", title: "Orden", label: "Ordenar" }),
				);

				let body;
				if (loading) {
					body = h(
						"ul",
						{ className: "mr-rows", "aria-busy": "true" },
						[0, 1, 2, 3, 4, 5].map((i) =>
							h(
								"li",
								{ key: i, className: "mr-row", style: { cursor: "default" } },
								h(
									"div",
									{ className: "mr-who", style: { gap: 6 } },
									h("span", { className: "mr-sk", style: { width: `${30 + ((i * 17) % 25)}%` } }),
									h("span", { className: "mr-sk", style: { width: `${45 + ((i * 11) % 30)}%`, height: 10 } }),
								),
							),
						),
					);
				} else if (visible.length === 0) {
					body = h(
						"p",
						{ className: "mr-empty" },
						query ? `Nada coincide con “${query}”.` : projects.length ? "Ningún proyecto en este estado." : "Todavía no hay proyectos. Tocá Actualizar para leer ~/Proyectos.",
					);
				} else {
					body = h(
						"div",
						{ className: "mr-groups" },
						groups.map((g) =>
							h(
								"section",
								{ key: g.key, className: "mr-group" },
								g.key === "flat"
									? null
									: h(
											"h2",
											{ className: "mr-group-head" },
											GROUP[g.key],
											h("span", { className: "n" }, String(g.rows.length)),
											g.key === "unclassified"
												? h("span", { className: "hint" }, "decidí: activo, pausado o archivado")
												: g.key === "active" && g.rows.length > 3
													? h("span", { className: "hint" }, "más de 3 activos: pausá alguno")
													: null,
										),
								h("ul", { className: "mr-rows" }, g.rows.map(rowView)),
							),
						),
					);
				}

				return h(React.Fragment, null, head, notices, bar, body);
			}

			function trashView() {
				const totalMb = trash.reduce((acc, t) => acc + Number(t.size_mb || 0), 0);
				return h(
					"div",
					{ className: "mr-detail" },
					h(
						"button",
						{ type: "button", className: "mr-crumb", onClick: () => setView("list"), title: "Volver (Esc)" },
						h(IconBack),
						"Proyectos",
					),
					notices,
					h(
						"div",
						{ className: "mr-dhead" },
						h(
							"div",
							{ className: "mr-dmain" },
							h("div", { className: "mr-dtitle" }, h("h1", null, "Papelera")),
							h(
								"p",
								{ className: "mr-ddesc" },
								trash.length
									? `${trash.length} proyecto(s) · ${totalMb.toFixed(1)} MB · el borrado automático llega a los ${RETENTION_DAYS} días`
									: "Vacía. Lo que borres pasa por acá antes de desaparecer.",
							),
						),
						trash.length
							? h(
									"div",
									{ className: "mr-actions" },
									h(
										"button",
										{
											type: "button",
											className: "mr-btn",
											"data-variant": "danger",
											onClick: () => setWiping(true),
										},
										"Vaciar papelera",
									),
								)
							: null,
					),
					trash.length
						? h(
								"ul",
								{ className: "mr-rows" },
								trash.map((t) =>
									h(
										"li",
										{ className: "mr-row", key: `${t.batch}-${t.slug}`, "data-trash": 1 },
										h(
											"div",
											{ className: "mr-who" },
											h("span", { className: "mr-name" }, t.slug),
											h(
												"span",
												{ className: "mr-sub" },
												`entró ${ageLabel(t.days)} · queda ${t.expires_in} día(s) antes del borrado automático`,
											),
										),
										h("span", { className: "mr-cell" }, `${t.size_mb} MB`),
										h(
											"span",
											{ className: "mr-trash-actions" },
											h(
												"button",
												{
													type: "button",
													className: "mr-btn",
													disabled: trashBusy === t.slug,
													onClick: () => recover(t.slug),
													title: "Devolver a ~/Proyectos",
												},
												trashBusy === t.slug ? "…" : "Restaurar",
											),
											h(
												"button",
												{
													type: "button",
													className: "mr-btn",
													"data-variant": "danger",
													disabled: trashBusy === t.slug,
													onClick: () => wipeOne(t.slug),
													title: "Borrar definitivamente",
												},
												"Borrar",
											),
										),
									),
								),
							)
						: null,
				);
			}

			function detailView() {
				const base = projects.find((p) => p.slug === selected) || { slug: selected, facts: {} };
				const d = detail || base;
				const f = d.facts || {};
				const tasks = (detail && detail.tasks) || [];
				const openTasks = tasks.filter((t) => t.state !== "done").length;
				const dirty = Number(f.dirty || 0);
				const ahead = String(f.ahead ?? "0");
				const remote = f.remote_url || "";
				const webRemote = remote.replace(/^git@([^:]+):/, "https://$1/").replace(/\.git$/, "");
				const desc = String(f.readme_excerpt || "").trim() || shortTitle(d);
				const home = (f.path || "").replace(/^\/home\/[^/]+/, "~");

				const kv = (label, value, opts) => {
					const o = opts || {};
					return h(
						"div",
						{ className: "mr-kv", key: label },
						h("dt", null, label),
						h("dd", { "data-tone": o.tone }, value, o.small ? h("small", null, o.small) : null),
					);
				};

				const addTask = async (input) => {
					const title = (input && input.value ? input.value : "").trim();
					if (!title) return;
					input.value = "";
					try {
						await api("/machine/task", { slug: d.slug, title });
					} catch (err) {
						setError(err.message);
					}
					refreshDetail(d.slug);
				};

				return h(
					"div",
					{ className: "mr-detail" },
					h(
						"button",
						{ type: "button", className: "mr-crumb", onClick: close, title: "Volver (Esc)" },
						h(IconBack),
						"Proyectos",
					),
					notices,
					h(
						"div",
						{ className: "mr-dhead" },
						h(
							"div",
							{ className: "mr-dmain" },
							h(
								"div",
								{ className: "mr-dtitle" },
								renaming
									? h("input", {
											className: "mr-field mr-rename",
											defaultValue: (d.title && d.title.trim()) || d.slug,
											autoFocus: true,
											onBlur: () => setRenaming(null),
											onKeyDown: async (event) => {
												if (event.key === "Escape") {
													setRenaming(null);
													return;
												}
												if (event.key !== "Enter") return;
												event.preventDefault();
												const value = event.target.value.trim();
												if (!value) return;
												try {
													await api("/machine/rename", { slug: d.slug, title: value });
													setRenaming(false);
													await load();
													refreshDetail(d.slug);
												} catch (err) {
													setError(err.message);
												}
											},
										})
									: h(
											"h1",
											{ onClick: () => setRenaming(true), title: "Clic para renombrar" },
											(d.title && d.title.trim()) || d.slug,
										),
								d.state
									? h(StateControl, { value: d.state, kind: d.kind, onChange: (next) => changeField(d.slug, "state", next) })
									: null,
							),
							(d.title && d.title.trim() && d.title.trim() !== d.slug)
								? h("p", { className: "mr-dpath" }, d.slug)
								: null,
							desc ? h("p", { className: "mr-ddesc" }, desc) : null,
							home ? h("p", { className: "mr-dpath" }, home) : null,
						),
						h(
							"div",
							{ className: "mr-dactions" },
							f.path
								? h(
										"button",
										{ type: "button", className: "mr-btn", onClick: () => openFolder(f.path), title: "Abrir la carpeta en el gestor de archivos" },
										h(IconFolder),
										"Abrir carpeta",
									)
								: null,
							h(
								"button",
								{
									type: "button",
									className: "mr-btn",
									"data-variant": "danger",
									onClick: () => setTrashing(d),
									title: "Mandar a la papelera…",
								},
								h(IconTrash),
								"Papelera",
							),
						),
					),
					h(
						"div",
						{ className: "mr-grid" },
						h(
							"section",
							{ className: "mr-section" },
							h("h2", { className: "mr-section-head" }, "Clasificación"),
							h(
								"dl",
								{ className: "mr-card", style: { margin: 0 } },
								kv(
									"Tipo",
									h(Dropdown, {
										value: d.kind || "project",
										options: KIND_OPTIONS,
										onChange: (next) => changeField(d.slug, "kind", next),
										plain: true,
										align: "end",
										title: "Cambiar tipo",
										label: "Tipo",
									}),
								),
								kv("Último cambio", ageLabel(d.age_days), {
									tone: d.age_days != null && d.age_days >= 30 ? "warn" : undefined,
								}),
								kv("Tareas abiertas", detail ? String(openTasks) : "…"),
							),
						),
						h(
							"section",
							{ className: "mr-section" },
							h("h2", { className: "mr-section-head" }, "Repositorio"),
							h(
								"dl",
								{ className: "mr-card", style: { margin: 0 } },
								kv("Rama", f.branch || "—", { tone: f.branch ? undefined : "quiet" }),
								kv("Último commit", f.last_commit || "—", {
									tone: f.last_commit ? undefined : "quiet",
									small: f.last_commit_subject || "",
								}),
								kv(
									"Peso",
									f.size_mb ? `${f.size_mb} MB` : "—",
									{ tone: f.size_mb ? undefined : "quiet", small: f.files ? `${f.files} archivos` : "" },
								),
								kv("Sin guardar", dirty > 0 ? plural(dirty, "archivo", "archivos") : "nada", {
									tone: dirty > 0 ? "warn" : "quiet",
								}),
								kv(
									"Sin subir",
									ahead === "?" ? "rama sin remoto" : ahead === "0" ? "nada" : plural(Number(ahead), "commit", "commits"),
									{ tone: ahead === "0" ? "quiet" : "warn" },
								),
								kv(
									"Remoto",
									remote
										? h(
												"a",
												{ href: webRemote, target: "_blank", rel: "noreferrer noopener" },
												webRemote.replace(/^https?:\/\//, ""),
											)
										: "sin remoto",
									{ tone: remote ? undefined : "warn" },
								),
								f.systemd === "true" ? kv("Servicio", "tiene unit systemd") : null,
							),
						),
					),
					h(
						"section",
						{ className: "mr-section" },
						h(
							"h2",
							{ className: "mr-section-head" },
							"Nota",
							h("span", { className: "aside" }, noteState === "saving" ? "guardando…" : noteState === "saved" ? "guardada" : "se guarda al salir del campo"),
						),
						h("textarea", {
							key: `${d.slug}-${detail ? "1" : "0"}`,
							className: "mr-field",
							defaultValue: d.note || "",
							placeholder: "Para qué es, en qué quedó, qué falta…",
							onBlur: async (event) => {
								const note = event.target.value;
								if (note === (d.note || "")) return;
								setNoteState("saving");
								try {
									await api("/machine/entity", { slug: d.slug, note });
									patch(d.slug, { note });
									setNoteState("saved");
								} catch (err) {
									setNoteState("");
									setError(err.message);
								}
							},
						}),
					),
					h(
						"section",
						{ className: "mr-section" },
						h("h2", { className: "mr-section-head" }, "Tareas", h("span", { className: "n" }, detail ? `${openTasks} abiertas` : "")),
						h(
							"ul",
							{ className: "mr-card mr-tasks" },
							!detail
								? h("li", null, h("span", { className: "mr-sk", style: { width: "40%", marginTop: 4 } }))
								: tasks.length === 0
									? h("li", { className: "mr-empty" }, "Todavía no hay tareas.")
									: tasks.map((t) =>
											h(
												"li",
												{ key: t.slug, "data-done": t.state === "done" ? 1 : 0 },
												h("input", {
													type: "checkbox",
													checked: t.state === "done",
													disabled: t.state === "done",
													title: t.state === "done" ? "Hecha" : "Marcar como hecha",
													onChange: async (event) => {
														if (!event.target.checked) return;
														try {
															await api("/machine/task-done", { task: t.slug });
														} catch (err) {
															setError(err.message);
														}
														refreshDetail(d.slug);
													},
												}),
												h("span", null, t.title),
											),
										),
						),
						h(
							"div",
							{ className: "mr-add" },
							h("input", {
								className: "mr-field",
								placeholder: "Nueva tarea",
								onKeyDown: (event) => {
									if (event.key === "Enter") addTask(event.currentTarget);
								},
							}),
							h(
								"button",
								{
									type: "button",
									className: "mr-btn",
									onClick: (event) => addTask(event.currentTarget.previousSibling),
								},
								"Agregar",
							),
						),
					),
				);
			}

			return h(
				"div",
				{ className: "mr", ref: scrollRef },
				view === "trash" ? trashView() : selected ? detailView() : listView(),
				wiping
					? h(WipeDialog, { count: trash.length, onCancel: () => setWiping(false), onConfirm: wipeAll })
					: null,
				trashing
					? h(TrashDialog, {
							project: trashing,
							onCancel: () => setTrashing(null),
							onDone: trashed,
						})
					: null,
			);
		}

		function MachineIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("rect", { x: 1.6, y: 1.6, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 9, y: 1.6, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 1.6, y: 9, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
				h("rect", { x: 9, y: 9, width: 5.4, height: 5.4, rx: 1.3, stroke: "currentColor", strokeWidth: 1.3 }),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("sidebar.panellist", () =>
				ctx.slots.register(
					{ name: "sidebar.panellist", id: PANEL_ID, order: 10, label: () => "Proyectos" },
					MachineIcon,
				),
			);
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({}) }, MachinePanel),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		return module.exports;
	},
});
