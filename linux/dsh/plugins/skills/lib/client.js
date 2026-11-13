/**
 * dsh-local-skills — client half.
 *
 * Panel "Skills" en la barra lateral, justo debajo de Plugins. Muestra el
 * catálogo del harness en una matriz de tarjetas (título + descripción) y, al
 * abrir una skill, renderiza su Markdown y permite editarlo.
 *
 * Datos: GET /skills/list, GET /skills/read?name y POST /skills/save
 * (mitad host de este plugin).
 */
window.__ModuleLoader__.load({
	id: "dsh-local-skills",
	factory: (require) => {
		const React = require("react");
		const h = React.createElement;

		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const PANEL_ID = "skills";
		const STYLE_ID = "dsh-skills-style";

		/** Origen del harness → nombre corto para la tarjeta. */
		const SOURCE_LABEL = {
			"user-agents": "usuario",
			"user-dsh": "usuario",
			"project-agents": "proyecto",
			"project-dsh": "proyecto",
			runtime: "plugin",
			bundled: "plugin",
			custom: "propia",
		};

		const CSS = `
.sk{
  --sk-fg: var(--dsw-alias-label-primary, #eceef2);
  --sk-fg2: var(--dsw-alias-label-secondary, #a3a8b3);
  --sk-fg3: var(--dsw-alias-label-tertiary, #737985);
  --sk-cap: var(--dsw-alias-label-caption, #737985);
  --sk-l1: var(--dsw-alias-border-l1, #ffffff0f);
  --sk-l2: var(--dsw-alias-border-l2, #ffffff1f);
  --sk-l3: var(--dsw-alias-border-l3, #ffffff29);
  --sk-l4: var(--dsw-alias-border-l4, #ffffff33);
  --sk-hover: var(--dsw-alias-interactive-bg-hover, #ffffff14);
  --sk-field: var(--dsw-alias-bg-layer-1, transparent);
  --sk-card: var(--dsw-alias-settings-card-fill, transparent);
  --sk-ok: var(--dsw-alias-state-success-primary, #2fb36b);
  --sk-info: var(--dsw-alias-state-business-primary, #4d6bfe);
  --sk-bad: var(--dsw-alias-state-error-primary, #f25a5a);
  --sk-mono: var(--ds-font-family-code, ui-monospace, SFMono-Regular, Menlo, monospace);
  --sk-r-sm: var(--dsw-radius-sm, 8px);
  --sk-r-md: var(--dsw-radius-md, 12px);
  --sk-ring: var(--dsw-focus-ring-width, 2px) solid var(--dsw-focus-ring-color, var(--sk-info));
  box-sizing:border-box;height:100%;min-height:0;overflow:auto;color:var(--sk-fg);
  display:flex;flex-direction:column;align-items:center;
  padding:0 clamp(20px,4vw,48px) 40px;font-size:13px;line-height:20px;
}
.sk *{box-sizing:border-box}
.sk>*{width:100%;max-width:960px}
:where(.sk) button,.sk textarea{font:inherit}
.sk :focus-visible{outline:var(--sk-ring);outline-offset:1px}

/* --- Cabecera ------------------------------------------------------------ */
.sk-head{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;flex-wrap:wrap;padding-top:24px}
.sk-titles{display:flex;flex-direction:column;gap:3px;min-width:0}
.sk-h1{margin:0;font-size:20px;font-weight:500;line-height:28px}
.sk-intro{margin:0;font-size:12.5px;line-height:18px;color:var(--sk-fg2);display:flex;flex-wrap:wrap;gap:0 6px;align-items:center}
.sk-intro b{font-weight:500;color:var(--sk-fg);font-variant-numeric:tabular-nums}
.sk-intro i{font-style:normal;color:var(--sk-cap)}
.sk-tools{display:flex;align-items:center;gap:8px;flex:none;min-width:0}
.sk-search{display:inline-flex;align-items:center;gap:6px;height:32px;width:230px;min-width:0;padding:0 10px;
  border:.5px solid var(--sk-l4);border-radius:var(--sk-r-md);background:var(--sk-field)}
.sk-search:focus-within{border-color:var(--sk-info)}
.sk-search svg{flex:none;color:var(--sk-fg3)}
.sk-search input{flex:1;min-width:0;border:0;outline:0;background:transparent;color:var(--sk-fg);
  font:inherit;font-size:13px;line-height:20px}
.sk-search input::placeholder{color:var(--sk-fg3)}

/* --- Botones ------------------------------------------------------------- */
.sk-btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;height:32px;padding:0 12px;
  border:.5px solid var(--sk-l4);border-radius:var(--sk-r-md);background:transparent;color:var(--sk-fg2);cursor:pointer;
  white-space:nowrap}
.sk-btn:hover{background:var(--sk-hover);color:var(--sk-fg)}
.sk-btn[disabled]{opacity:.5;cursor:default}
.sk-btn.primary{border-color:transparent;background:var(--sk-info);color:#fff}
.sk-btn.primary:hover{filter:brightness(1.08)}
.sk-btn.quiet{border-color:transparent;padding:0 8px}

/* --- Matriz de tarjetas -------------------------------------------------- */
.sk-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(214px,1fr));gap:12px;margin-top:20px}
.sk-card{display:flex;flex-direction:column;justify-content:space-between;gap:10px;min-height:120px;
  padding:13px 14px;text-align:left;color:inherit;cursor:pointer;
  border:.5px solid var(--sk-l2);border-radius:var(--sk-r-md);background:var(--sk-card)}
.sk-card:hover{border-color:var(--sk-l3);background:var(--sk-hover)}
.sk-card-title{font-family:var(--sk-mono);font-size:12.5px;line-height:18px;font-weight:500;color:var(--sk-fg);
  display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:anywhere}
.sk-card-desc{font-size:12px;line-height:17px;color:var(--sk-fg2);
  display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.sk-card-foot{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:auto}
.sk-tags{display:flex;gap:4px;align-items:center;flex-wrap:wrap}
.sk-tag{display:inline-flex;align-items:center;height:17px;padding:0 6px;border-radius:999px;
  border:.5px solid var(--sk-l4);font-size:10.5px;line-height:15px;color:var(--sk-fg2);white-space:nowrap}
.sk-tag.model{color:var(--sk-info);border-color:color-mix(in srgb, var(--sk-info) 45%, transparent)}
.sk-tag.cmd{color:var(--sk-ok);border-color:color-mix(in srgb, var(--sk-ok) 40%, transparent)}
.sk-src{font-size:10.5px;line-height:15px;color:var(--sk-cap);white-space:nowrap}

/* --- Estados ------------------------------------------------------------- */
.sk-empty{margin:22px 0 0;font-size:13px;line-height:20px;color:var(--sk-fg2)}
.sk-note{margin:20px 0 0;font-size:11.5px;line-height:17px;color:var(--sk-fg3);overflow-wrap:anywhere}
.sk-error{margin:12px 0 0;font-size:12.5px;line-height:18px;color:var(--sk-bad)}
.sk-skel{display:grid;grid-template-columns:repeat(auto-fill,minmax(214px,1fr));gap:12px;margin-top:20px}
.sk-sk{height:120px;border-radius:var(--sk-r-md);background:var(--sk-l1);border:.5px solid var(--sk-l1);
  animation:sk-pulse 1.4s ease-in-out infinite}
@keyframes sk-pulse{0%,100%{opacity:.45}50%{opacity:1}}
@media (prefers-reduced-motion:reduce){.sk-sk{animation:none;opacity:.7}}
.sk-ignored{margin-top:18px;font-size:11.5px;line-height:17px;color:var(--sk-fg3)}
.sk-ignored summary{cursor:pointer}
.sk-ignored-list{list-style:none;margin:6px 0 0;padding:0;display:flex;flex-direction:column;gap:2px}
.sk-ignored-list li{display:flex;gap:8px;flex-wrap:wrap}
.sk-ignored-list .n{font-family:var(--sk-mono);color:var(--sk-fg2)}
.sk-ignored-list .r{color:var(--sk-cap)}

/* --- Detalle ------------------------------------------------------------- */
.sk-detail{display:flex;flex-direction:column;gap:14px;padding:20px 0 8px}
.sk-crumb{display:inline-flex;align-items:center;gap:6px;align-self:flex-start;height:26px;padding:0 8px;
  margin-left:-8px;border:0;border-radius:var(--sk-r-sm);background:transparent;color:var(--sk-fg2);cursor:pointer}
.sk-crumb:hover{background:var(--sk-hover);color:var(--sk-fg)}
.sk-dhead{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap}
.sk-dmain{display:flex;flex-direction:column;gap:6px;min-width:0}
.sk-dtitle{margin:0;font-size:19px;font-weight:500;line-height:26px;font-family:var(--sk-mono);overflow-wrap:anywhere}
.sk-dmeta{display:flex;flex-wrap:wrap;align-items:center;gap:6px;font-size:11.5px;line-height:17px;color:var(--sk-cap)}
.sk-dmeta .p{font-family:var(--sk-mono);color:var(--sk-fg3);overflow-wrap:anywhere}
.sk-ddesc{margin:0;font-size:12.5px;line-height:18px;color:var(--sk-fg2);max-width:760px}
.sk-dactions{display:flex;gap:8px;align-items:center;flex-wrap:wrap;flex:none}

/* --- Markdown renderizado ------------------------------------------------ */
.sk-prose{max-width:780px;font-size:13.5px;line-height:21px;color:var(--sk-fg)}
.sk-prose>*:first-child{margin-top:0}
.sk-prose h2{margin:24px 0 8px;font-size:17px;line-height:24px;font-weight:500}
.sk-prose h3{margin:20px 0 6px;font-size:15px;line-height:22px;font-weight:500}
.sk-prose h4{margin:16px 0 4px;font-size:13.5px;line-height:20px;font-weight:600}
.sk-prose h5,.sk-prose h6{margin:14px 0 4px;font-size:12.5px;line-height:18px;font-weight:600;color:var(--sk-fg2)}
.sk-prose p{margin:0 0 10px}
.sk-prose ul,.sk-prose ol{margin:0 0 10px;padding-left:20px}
.sk-prose li{margin:3px 0}
.sk-prose code{font-family:var(--sk-mono);font-size:12px;background:var(--sk-l2);padding:1px 5px;border-radius:5px}
.sk-prose pre{margin:0 0 12px;padding:12px 14px;border:.5px solid var(--sk-l2);border-radius:var(--sk-r-sm);
  overflow:auto;background:var(--sk-field)}
.sk-prose pre code{background:transparent;padding:0;font-size:12px;line-height:18px}
.sk-prose blockquote{margin:0 0 12px;padding:2px 0 2px 12px;border-left:2px solid var(--sk-l4);color:var(--sk-fg2)}
.sk-prose hr{border:0;border-top:.5px solid var(--sk-l2);margin:18px 0}
.sk-prose table{border-collapse:collapse;margin:0 0 12px;font-size:12.5px;display:block;overflow-x:auto}
.sk-prose th,.sk-prose td{border:.5px solid var(--sk-l2);padding:5px 9px;text-align:left;vertical-align:top}
.sk-prose th{background:var(--sk-l1);font-weight:500}
.sk-prose a{color:var(--sk-info);text-decoration:none}
.sk-prose a:hover{text-decoration:underline}

/* --- Editor -------------------------------------------------------------- */
.sk-editor{width:100%;min-height:340px;padding:13px 14px;border:.5px solid var(--sk-l4);border-radius:var(--sk-r-sm);
  background:var(--sk-field);color:var(--sk-fg);font-family:var(--sk-mono);font-size:12.5px;line-height:19px;
  resize:vertical;tab-size:2;overflow:hidden}
.sk-editor:focus{outline:none;border-color:var(--sk-info)}
.sk-editbar{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.sk-hint{font-size:11.5px;line-height:16px;color:var(--sk-cap)}

/* --- Celular: 2 columnas, campos de 16px, objetivos de 36px -------------- */
@media (max-width:820px){
  .sk{padding:0 14px 28px}
  .sk-head{padding-top:16px;gap:10px}
  .sk-tools{width:100%}
  .sk-search{flex:1;width:auto;height:36px}
  .sk-search input{font-size:16px}
  .sk-btn{height:36px}
  .sk-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:14px}
  .sk-card{min-height:104px;padding:11px 12px}
  .sk-card-title{font-size:12px;line-height:17px}
  .sk-card-desc{font-size:11.5px;line-height:16px;-webkit-line-clamp:2}
  .sk-src{display:none}
  .sk-skel{grid-template-columns:repeat(2,minmax(0,1fr))}
  .sk-detail{padding-top:14px}
  .sk-dtitle{font-size:17px;line-height:24px}
  .sk-prose{font-size:14px;line-height:22px}
  .sk-editor{font-size:16px;line-height:22px}
  .sk-dactions{width:100%}
  .sk-dactions .sk-btn{flex:none}
}
`;

		const ICON_SEARCH = h(
			"svg",
			{ width: 14, height: 14, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
			h("circle", { cx: 7, cy: 7, r: 4.2, stroke: "currentColor", strokeWidth: 1.3 }),
			h("path", { d: "M10.2 10.2 14 14", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round" }),
		);
		const ICON_BACK = h(
			"svg",
			{ width: 14, height: 14, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
			h("path", {
				d: "M9.5 3.5 5 8l4.5 4.5",
				stroke: "currentColor",
				strokeWidth: 1.4,
				strokeLinecap: "round",
				strokeLinejoin: "round",
			}),
		);

		function ensureStyle() {
			if (document.getElementById(STYLE_ID) !== null) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = CSS;
			document.head.appendChild(style);
		}

		async function getJson(path) {
			const res = await fetch(path, { headers: { accept: "application/json" } });
			const body = await res.json().catch(() => null);
			if (!res.ok || body === null || body.ok !== true) {
				throw new Error((body && body.error) || `HTTP ${res.status}`);
			}
			return body;
		}

		/** Separa el frontmatter del cuerpo: el cuerpo es lo que se renderiza. */
		function splitFrontmatter(text) {
			const match = text.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
			if (match === null) return { head: "", body: text };
			return { head: match[0], body: text.slice(match[0].length) };
		}

		function matches(skill, terms) {
			if (terms.length === 0) return true;
			const haystack = `${skill.name} ${skill.description} ${skill.whenToUse} ${skill.source}`.toLowerCase();
			return terms.every((term) => haystack.includes(term));
		}

		/* --- Markdown mínimo y seguro (sin HTML crudo) --------------------- */

		const INLINE_RE =
			/(`[^`\n]+`|\*\*[^*\n]+\*\*|__[^_\n]+__|\*[^*\n]+\*|_[^_\n]+_|\[[^\]\n]+\]\((?:https?:\/\/[^)\s]+)\))/g;

		function inline(text, prefix) {
			const out = [];
			let last = 0;
			let index = 0;
			let match = INLINE_RE.exec(text);
			while (match !== null) {
				if (match.index > last) out.push(text.slice(last, match.index));
				const token = match[0];
				const key = `${prefix}-${index}`;
				index += 1;
				if (token.startsWith("`")) {
					out.push(h("code", { key }, token.slice(1, -1)));
				} else if (token.startsWith("**") || token.startsWith("__")) {
					out.push(h("strong", { key }, token.slice(2, -2)));
				} else if (token.startsWith("[")) {
					const link = token.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
					out.push(h("a", { key, href: link[2], target: "_blank", rel: "noreferrer noopener" }, link[1]));
				} else {
					out.push(h("em", { key }, token.slice(1, -1)));
				}
				last = match.index + token.length;
				match = INLINE_RE.exec(text);
			}
			if (last < text.length) out.push(text.slice(last));
			return out;
		}

		function splitRow(line) {
			return line
				.trim()
				.replace(/^\|/, "")
				.replace(/\|$/, "")
				.split("|")
				.map((cell) => cell.trim());
		}

		/** Markdown → elementos React. Títulos, listas, código, tablas, citas y links. */
		function renderMarkdown(text) {
			const lines = text.split(/\r?\n/);
			const blocks = [];
			let i = 0;
			let key = 0;
			while (i < lines.length) {
				const line = lines[i];
				if (/^\s*$/.test(line)) {
					i += 1;
					continue;
				}
				const fence = line.match(/^\s*(```|~~~)([A-Za-z0-9+#-]*)\s*$/);
				if (fence !== null) {
					const buffer = [];
					const marker = fence[1];
					i += 1;
					while (i < lines.length && !new RegExp(`^\\s*${marker}\\s*$`).test(lines[i])) {
						buffer.push(lines[i]);
						i += 1;
					}
					i += 1;
					blocks.push(h("pre", { key: key++ }, h("code", null, buffer.join("\n"))));
					continue;
				}
				const heading = line.match(/^(#{1,6})\s+(.*)$/);
				if (heading !== null) {
					const level = Math.min(heading[1].length + 1, 6);
					blocks.push(h(`h${level}`, { key: key++ }, inline(heading[2], `h${key}`)));
					i += 1;
					continue;
				}
				if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
					blocks.push(h("hr", { key: key++ }));
					i += 1;
					continue;
				}
				if (/^\s*>\s?/.test(line)) {
					const buffer = [];
					while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
						buffer.push(lines[i].replace(/^\s*>\s?/, ""));
						i += 1;
					}
					blocks.push(h("blockquote", { key: key++ }, h("p", null, inline(buffer.join(" "), `bq${key}`))));
					continue;
				}
				if (/^\s*([-*+]|\d+[.)])\s+/.test(line)) {
					const ordered = /^\s*\d+[.)]\s+/.test(line);
					const items = [];
					let item = "";
					while (i < lines.length && /^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) {
						if (item.length > 0) items.push(item);
						item = lines[i].replace(/^\s*([-*+]|\d+[.)])\s+/, "");
						i += 1;
						while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*+]|\d+[.)])\s+/.test(lines[i])) {
							item += ` ${lines[i].trim()}`;
							i += 1;
						}
					}
					if (item.length > 0) items.push(item);
					blocks.push(
						h(
							ordered ? "ol" : "ul",
							{ key: key++ },
							items.map((entry, index) => h("li", { key: index }, inline(entry, `li${key}${index}`))),
						),
					);
					continue;
				}
				if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
					const header = splitRow(lines[i]);
					i += 2;
					const rows = [];
					while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
						rows.push(splitRow(lines[i]));
						i += 1;
					}
					blocks.push(
						h(
							"table",
							{ key: key++ },
							h(
								"thead",
								null,
								h(
									"tr",
									null,
									header.map((cell, ci) => h("th", { key: ci }, inline(cell, `th${key}${ci}`))),
								),
							),
							h(
								"tbody",
								null,
								rows.map((row, ri) =>
									h(
										"tr",
										{ key: ri },
										row.map((cell, ci) => h("td", { key: ci }, inline(cell, `td${key}${ri}${ci}`))),
									),
								),
							),
						),
					);
					continue;
				}
				const buffer = [];
				while (
					i < lines.length &&
					!/^\s*$/.test(lines[i]) &&
					!/^\s*(#{1,6}\s|```|~~~|>|\|)/.test(lines[i]) &&
					!/^\s*([-*+]|\d+[.)])\s+/.test(lines[i])
				) {
					buffer.push(lines[i]);
					i += 1;
				}
				blocks.push(h("p", { key: key++ }, inline(buffer.join(" "), `p${key}`)));
			}
			return blocks;
		}

		function tagsFor(skill) {
			const tags = [];
			if (skill.model) tags.push(h("span", { key: "m", className: "sk-tag model" }, "modelo"));
			if (skill.user) {
				tags.push(h("span", { key: "u", className: "sk-tag cmd" }, skill.model ? "comando" : "solo comando"));
			}
			if (tags.length === 0) tags.push(h("span", { key: "n", className: "sk-tag" }, "oculta"));
			return tags;
		}

		function SkillCard(props) {
			const skill = props.skill;
			return h(
				"button",
				{
					type: "button",
					className: "sk-card",
					onClick: () => props.onOpen(skill.name),
					title: skill.path ? `${skill.name} — ${skill.path}` : skill.name,
				},
				h(
					"div",
					{ className: "sk-titles" },
					h("span", { className: "sk-card-title" }, skill.name),
					skill.description ? h("span", { className: "sk-card-desc" }, skill.description) : null,
				),
				h(
					"div",
					{ className: "sk-card-foot" },
					h("div", { className: "sk-tags" }, tagsFor(skill)),
					h("span", { className: "sk-src" }, SOURCE_LABEL[skill.source] ?? skill.source),
				),
			);
		}

		function Detail(props) {
			const { skill, status, error, onBack, onSaved, onRetry } = props;
			const [editing, setEditing] = React.useState(false);
			const [draft, setDraft] = React.useState("");
			const [saving, setSaving] = React.useState(false);
			const [saveError, setSaveError] = React.useState("");
			const [copied, setCopied] = React.useState(false);
			const editorRef = React.useRef(null);

			// El editor crece con el contenido: nada de un scroll dentro de otro.
			React.useEffect(() => {
				const editor = editorRef.current;
				if (!editing || editor === null) return;
				editor.style.height = "auto";
				editor.style.height = `${editor.scrollHeight + 2}px`;
			}, [editing, draft]);

			React.useEffect(() => {
				if (!copied) return undefined;
				const timer = setTimeout(() => setCopied(false), 1400);
				return () => clearTimeout(timer);
			}, [copied]);

			if (status === "loading") {
				return h(
					"div",
					{ className: "sk-detail", "aria-busy": "true" },
					h("button", { type: "button", className: "sk-crumb", onClick: onBack }, ICON_BACK, "Skills"),
					h("div", { className: "sk-skel" }, [0, 1, 2].map((i) => h("span", { key: i, className: "sk-sk" }))),
				);
			}
			if (status === "error") {
				return h(
					"div",
					{ className: "sk-detail" },
					h("button", { type: "button", className: "sk-crumb", onClick: onBack }, ICON_BACK, "Skills"),
					h("p", { className: "sk-error" }, `No pude leer la skill: ${error}`),
					h("button", { type: "button", className: "sk-btn", onClick: onRetry }, "Reintentar"),
				);
			}

			const content = typeof skill.content === "string" ? skill.content : "";
			const body = splitFrontmatter(content).body;
			const dirty = editing && draft !== content;

			function startEdit() {
				setDraft(content);
				setSaveError("");
				setEditing(true);
			}

			function cancelEdit() {
				if (draft !== content && !window.confirm("¿Descartar los cambios sin guardar?")) return;
				setEditing(false);
				setSaveError("");
			}

			async function save() {
				if (saving) return;
				setSaving(true);
				setSaveError("");
				try {
					const res = await fetch("/skills/save", {
						method: "POST",
						headers: { "content-type": "application/json", "x-dsh-skills": "1" },
						body: JSON.stringify({ name: skill.name, content: draft }),
					});
					const payload = await res.json().catch(() => null);
					if (!res.ok || payload === null || payload.ok !== true) {
						if (res.status === 404 || res.status === 405) {
							throw new Error("el servidor todavía no tiene la ruta de guardado: reiniciá dsh-web");
						}
						throw new Error((payload && payload.error) || `HTTP ${res.status}`);
					}
					setEditing(false);
					onSaved(payload.skill);
				} catch (failure) {
					setSaveError(failure instanceof Error ? failure.message : String(failure));
				} finally {
					setSaving(false);
				}
			}

			function leave() {
				if (dirty && !window.confirm("Tenés cambios sin guardar. ¿Salir igual?")) return;
				onBack();
			}

			return h(
				"div",
				{ className: "sk-detail" },
				h("button", { type: "button", className: "sk-crumb", onClick: leave, title: "Volver (Esc)" }, ICON_BACK, "Skills"),
				h(
					"div",
					{ className: "sk-dhead" },
					h(
						"div",
						{ className: "sk-dmain" },
						h("h1", { className: "sk-dtitle" }, skill.name),
						h(
							"div",
							{ className: "sk-dmeta" },
							h("div", { className: "sk-tags" }, tagsFor(skill)),
							h("span", null, SOURCE_LABEL[skill.source] ?? skill.source),
							skill.path ? h("span", { className: "p" }, skill.path) : null,
						),
					),
					h(
						"div",
						{ className: "sk-dactions" },
						skill.path
							? h(
									"button",
									{
										type: "button",
										className: "sk-btn quiet",
										onClick: () => {
											Promise.resolve(navigator.clipboard?.writeText(skill.path)).then(
												() => setCopied(true),
												() => setCopied(false),
											);
										},
									},
									copied ? "Copiada" : "Copiar ruta",
								)
							: null,
						editing ? null : h("button", { type: "button", className: "sk-btn primary", onClick: startEdit }, "Editar"),
					),
				),
				skill.description && !editing ? h("p", { className: "sk-ddesc" }, skill.description) : null,
				saveError ? h("p", { className: "sk-error" }, `No se guardó: ${saveError}`) : null,
				editing
					? h(
							React.Fragment,
							null,
							h("textarea", {
								ref: editorRef,
								className: "sk-editor",
								value: draft,
								spellCheck: false,
								"aria-label": `Editar ${skill.name}`,
								onChange: (event) => setDraft(event.target.value),
								onKeyDown: (event) => {
									if (event.key === "Escape") {
										event.preventDefault();
										event.stopPropagation();
										cancelEdit();
										return;
									}
									if (event.key === "s" && (event.metaKey || event.ctrlKey)) {
										event.preventDefault();
										save();
									}
								},
							}),
							h(
								"div",
								{ className: "sk-editbar" },
								h(
									"button",
									{ type: "button", className: "sk-btn primary", onClick: save, disabled: saving },
									saving ? "Guardando…" : "Guardar",
								),
								h("button", { type: "button", className: "sk-btn", onClick: cancelEdit, disabled: saving }, "Cancelar"),
								h(
									"span",
									{ className: "sk-hint" },
									"⌘/Ctrl+S guarda · Esc cancela · el frontmatter necesita name y description",
								),
							),
						)
					: h("div", { className: "sk-prose" }, renderMarkdown(body)),
			);
		}

		function SkillsPanel() {
			const [state, setState] = React.useState({ status: "loading" });
			const [query, setQuery] = React.useState("");
			const [detail, setDetail] = React.useState(null);
			const [notice, setNotice] = React.useState("");
			const searchRef = React.useRef(null);

			const load = React.useCallback(async () => {
				setState((prev) => (prev.status === "ready" ? { ...prev, refreshing: true } : { status: "loading" }));
				try {
					const data = await getJson("/skills/list");
					setState({ status: "ready", data });
				} catch (error) {
					setState({ status: "error", error: error instanceof Error ? error.message : String(error) });
				}
			}, []);

			React.useEffect(() => {
				ensureStyle();
				load();
			}, [load]);

			React.useEffect(() => {
				if (notice.length === 0) return undefined;
				const timer = setTimeout(() => setNotice(""), 2400);
				return () => clearTimeout(timer);
			}, [notice]);

			const openSkill = React.useCallback(async (name) => {
				setDetail({ status: "loading", name });
				try {
					const payload = await getJson(`/skills/read?name=${encodeURIComponent(name)}`);
					setDetail({ status: "ready", name, skill: payload.skill });
				} catch (error) {
					setDetail({ status: "error", name, error: error instanceof Error ? error.message : String(error) });
				}
			}, []);

			React.useEffect(() => {
				function onKey(event) {
					if (event.key === "Escape" && detail !== null) {
						if (event.target instanceof HTMLElement && event.target.tagName === "TEXTAREA") return;
						event.preventDefault();
						setDetail(null);
						return;
					}
					const typing =
						event.target instanceof HTMLElement && /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
					if (event.key === "/" && !typing && detail === null) {
						event.preventDefault();
						searchRef.current?.focus();
					}
				}
				window.addEventListener("keydown", onKey);
				return () => window.removeEventListener("keydown", onKey);
			}, [detail]);

			if (detail !== null) {
				return h(
					"div",
					{ className: "sk" },
					h(Detail, {
						key: detail.skill?.name ?? detail.name,
						status: detail.status,
						skill: detail.skill,
						error: detail.error,
						onBack: () => setDetail(null),
						onRetry: () => openSkill(detail.name),
						onSaved: (skill) => {
							setDetail({ status: "ready", name: skill.name, skill });
							setNotice("Guardado");
							load();
						},
					}),
				);
			}

			const ready = state.status === "ready";
			const skills = ready ? state.data.skills : [];
			const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
			const visible = skills.filter((skill) => matches(skill, terms));

			return h(
				"div",
				{ className: "sk" },
				h(
					"header",
					{ className: "sk-head" },
					h(
						"div",
						{ className: "sk-titles" },
						h("h1", { className: "sk-h1" }, "Skills"),
						ready
							? h(
									"p",
									{ className: "sk-intro" },
									h("span", null, h("b", null, String(state.data.count)), " skills"),
									h("i", null, "·"),
									h("span", null, h("b", null, String(state.data.model)), " las ve el modelo"),
									h("i", null, "·"),
									h("span", null, h("b", null, String(state.data.command)), " solo por /comando"),
									notice.length > 0 ? h("i", { style: { color: "var(--sk-ok)" } }, `· ${notice}`) : null,
								)
							: h("p", { className: "sk-intro" }, h("span", null, "Leyendo el catálogo…")),
					),
					h(
						"div",
						{ className: "sk-tools" },
						h(
							"label",
							{ className: "sk-search" },
							ICON_SEARCH,
							h("input", {
								ref: searchRef,
								type: "search",
								value: query,
								placeholder: "Buscar skill",
								"aria-label": "Buscar skill",
								onChange: (event) => setQuery(event.target.value),
								onKeyDown: (event) => {
									if (event.key === "Escape") setQuery("");
								},
							}),
						),
						h(
							"button",
							{ type: "button", className: "sk-btn", onClick: load, disabled: ready && state.refreshing === true },
							ready && state.refreshing === true ? "Actualizando…" : "Actualizar",
						),
					),
				),
				state.status === "error"
					? h(
							"div",
							null,
							h("p", { className: "sk-error" }, `No pude leer las skills: ${state.error}`),
							h("p", { className: "sk-note" }, "El endpoint /skills/list no respondió. Revisá el log de dsh-web."),
						)
					: null,
				state.status === "loading"
					? h(
							"div",
							{ className: "sk-skel", "aria-busy": "true" },
							[0, 1, 2, 3, 4, 5].map((i) => h("span", { key: i, className: "sk-sk" })),
						)
					: null,
				ready
					? h(
							"div",
							{ className: "sk-grid" },
							visible.map((skill) => h(SkillCard, { key: skill.name, skill, onOpen: openSkill })),
						)
					: null,
				ready && visible.length === 0
					? h("p", { className: "sk-empty" }, query ? `Nada coincide con “${query}”.` : "No hay skills cargadas.")
					: null,
				ready && state.data.ignored.length > 0
					? h(
							"details",
							{ className: "sk-ignored" },
							h("summary", null, `${state.data.ignored.length} entrada(s) que el harness no carga`),
							h(
								"ul",
								{ className: "sk-ignored-list" },
								state.data.ignored.map((item, index) =>
									h(
										"li",
										{ key: `${item.name}-${index}` },
										h("span", { className: "n" }, item.name),
										h("span", { className: "r" }, item.reason),
									),
								),
							),
						)
					: null,
				ready
					? h(
							"p",
							{ className: "sk-note" },
							`Leyendo ${state.data.roots
								.filter((root) => root.exists)
								.map((root) => root.path)
								.join(" · ")}`,
						)
					: null,
			);
		}

		function SkillsIcon(props) {
			const size = props?.size ?? 16;
			return h(
				"svg",
				{ width: size, height: size, viewBox: "0 0 16 16", fill: "none", "aria-hidden": "true" },
				h("path", {
					d: "M7 1.8 8.35 5.1 11.7 6.45 8.35 7.8 7 11.1 5.65 7.8 2.3 6.45 5.65 5.1Z",
					fill: "currentColor",
				}),
				h("path", {
					d: "M11.9 9.4 12.55 10.9 14.1 11.55 12.55 12.2 11.9 13.7 11.25 12.2 9.7 11.55 11.25 10.9Z",
					fill: "currentColor",
					opacity: 0.7,
				}),
			);
		}

		function apply(ctx) {
			ctx.slots.inject("sidebar.panellist", () =>
				ctx.slots.register(
					{ name: "sidebar.panellist", id: PANEL_ID, order: 1, label: () => "Skills" },
					SkillsIcon,
				),
			);
			ctx.slots.inject("main", () =>
				ctx.slots.register({ name: "main", key: PANEL_ID, inject: () => ({}) }, SkillsPanel),
			);
		}

		exports.apply = apply;
		exports.inject = ["slots"];
		// Solo para pruebas sin navegador (no lo usa la UI).
		exports.__test = { renderMarkdown, splitFrontmatter, inline };
		return module.exports;
	},
});
