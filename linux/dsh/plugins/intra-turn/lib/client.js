/**
 * dsh-local-intra-turn — client half.
 *
 * Feedforward, tal cual la demo: mientras escribís en el compositor, el modelo
 * dice qué va a asumir por vos y qué le falta saber, y vos lo corregís antes de
 * mandar.
 *
 * El compositor del harness es Lexical (contenteditable), no un <textarea>:
 * se lee con innerText, los cambios se detectan con un MutationObserver y
 * "Aplicar" agrega nodos al estado de Lexical (ver appendToComposer).
 */
window.__ModuleLoader__.load({
	id: "dsh-local-intra-turn",
	factory: () => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const ENDPOINT = "/intra-turn/feedforward";
		const STYLE_ID = "dsh-intra-turn-style";
		const PANEL_ID = "dsh-intra-turn-panel";
		const DEBOUNCE_MS = 900;
		const MIN_CHARS = 12;
		const HEADING = "Tené en cuenta:";

		let panel = null;
		let timer = null;
		let lastAnalyzed = "";
		let current = { assumptions: [], missing: [] };
		let seq = 0;
		let inflight = null;
		let observed = null;
		let observer = null;
		let cardObserver = null;

		const esc = (value) =>
			String(value ?? "").replace(/[&<>"']/g, (c) => ({
				"&": "&amp;",
				"<": "&lt;",
				">": "&gt;",
				'"': "&quot;",
				"'": "&#39;",
			}[c]));

		/** Editor de Lexical del compositor. */
		function composer() {
			const direct = document.querySelector('[data-composer-input] [data-lexical-editor="true"], [data-lexical-editor="true"]');
			if (direct) return direct;
			const editables = Array.from(document.querySelectorAll('div[contenteditable="true"]'));
			return editables.length > 0 ? editables[editables.length - 1] : null;
		}

		/** Tarjeta del compositor (texto + botones): el panel se alinea con ella. */
		function composerCard(editor) {
			return editor?.closest("[data-composer-card]") ?? editor;
		}

		/** Id de la sesión que se está mirando (lo escribe el renderer). */
		function sessionIdOf() {
			const scroll = document.querySelector("[data-conversation-scroll]");
			const host = scroll?.closest("[data-conversation-content]") ?? scroll?.parentElement;
			const id = host?.getAttribute("data-conversation-session");
			return typeof id === "string" && id.length > 0 ? id : "";
		}

		function draftText(node) {
			return String(node?.innerText ?? node?.textContent ?? "").replace(/ /g, " ").trim();
		}

		function injectStyles() {
			if (document.getElementById(STYLE_ID)) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = `
#${PANEL_ID}{position:fixed;z-index:1000;display:flex;flex-direction:column;box-sizing:border-box;
  border-radius:var(--dsw-radius-lg,16px);background:var(--dsw-alias-bg-layer-2,#2c2c2e);
  color:var(--dsw-alias-label-primary,#f9fafb);
  box-shadow:0 0 0 .5px var(--dsw-alias-border-l2,#ffffff1f),0 12px 32px rgba(0,0,0,.35);
  font:400 13px/1.45 var(--dsw-font-family,system-ui,sans-serif);overflow:hidden}
#${PANEL_ID} *{box-sizing:border-box}
#${PANEL_ID} header{display:flex;align-items:baseline;gap:8px;padding:10px 14px 6px;flex:none}
#${PANEL_ID} header strong{font-weight:500;font-size:13px;color:var(--dsw-alias-label-secondary,#cfd3d6)}
#${PANEL_ID} header .hint{margin-left:auto;font-size:11.5px;color:var(--dsw-alias-label-caption,#81858c);white-space:nowrap}
#${PANEL_ID} .body{padding:4px 14px 10px;display:flex;flex-direction:column;gap:8px;overflow:auto;min-height:0}
#${PANEL_ID} .row{display:grid;grid-template-columns:minmax(96px,28%) 1fr;align-items:start;gap:4px 10px}
#${PANEL_ID} .row > label{padding-top:6px;color:var(--dsw-alias-label-tertiary,#adb2b8);font-size:12px;line-height:1.3}
#${PANEL_ID} .val{min-width:0;display:flex;align-items:center;gap:6px;flex-wrap:wrap}
#${PANEL_ID} input.mit{flex:1 1 140px;min-width:0;height:30px;padding:0 10px;
  border:1px solid var(--dsw-alias-border-l2,#ffffff1f);border-radius:var(--dsw-radius-sm,8px);
  background:var(--dsw-alias-bg-layer-1,#232324);color:inherit;font:inherit;font-size:13px;outline:none}
#${PANEL_ID} input.mit::placeholder{color:var(--dsw-alias-label-caption,#81858c)}
#${PANEL_ID} input.mit:focus{border-color:var(--dsw-alias-border-l4,#fff3)}
#${PANEL_ID} button.chip{height:28px;padding:0 10px;border:1px solid var(--dsw-alias-border-l2,#ffffff1f);border-radius:999px;
  background:transparent;color:var(--dsw-alias-label-secondary,#cfd3d6);font:inherit;font-size:12.5px;cursor:pointer;white-space:nowrap;
  max-width:100%;overflow:hidden;text-overflow:ellipsis}
#${PANEL_ID} button.chip:hover{background:var(--dsw-alias-interactive-bg-hover,#ffffff14);color:var(--dsw-alias-label-primary,#f9fafb)}
#${PANEL_ID} button.chip[data-on="1"]{background:var(--dsw-alias-button-ghost-active-fill,#43454a);
  border-color:var(--dsw-alias-button-ghost-active-border,#81858c);color:var(--dsw-alias-label-primary,#f9fafb)}
#${PANEL_ID} footer{display:flex;align-items:center;gap:8px;padding:8px 14px 12px;flex:none}
#${PANEL_ID} footer .note{flex:1;min-width:0;font-size:11.5px;color:var(--dsw-alias-label-caption,#81858c)}
#${PANEL_ID} footer .note[data-error="1"]{color:var(--dsw-alias-state-error-primary,#f25a5a)}
#${PANEL_ID} button.btn{height:30px;padding:0 12px;border:0;border-radius:999px;background:transparent;
  color:var(--dsw-alias-label-secondary,#cfd3d6);font:inherit;font-size:13px;cursor:pointer}
#${PANEL_ID} button.btn:hover{background:var(--dsw-alias-interactive-bg-hover,#ffffff14)}
#${PANEL_ID} button.btn.primary{background:var(--dsw-alias-button-primary-fill,#f9fafb);
  color:var(--dsw-alias-label-primary-foreground,#0f1115);font-weight:500}
#${PANEL_ID} button.btn.primary:hover{background:var(--dsw-alias-button-primary-hover,#ebeef2)}
@media (max-width:560px){
  #${PANEL_ID} .row{grid-template-columns:1fr}
  #${PANEL_ID} .row > label{padding-top:0}
  #${PANEL_ID} header .hint,#${PANEL_ID} footer .note:not([data-error="1"]){display:none}
}
`;
			document.head.appendChild(style);
		}

		function closePanel() {
			if (panel) panel.remove();
			panel = null;
			cardObserver?.disconnect();
			cardObserver = null;
			document.removeEventListener("mousedown", onOutside, true);
		}

		function onOutside(event) {
			if (!panel) return;
			if (panel.contains(event.target)) return;
			const editor = composer();
			if (editor && editor.contains(event.target)) return;
			closePanel();
		}

		/**
		 * Pegado a la tarjeta del compositor, mismo ancho. Arriba cuando está al pie
		 * (conversación); abajo si hay más lugar abajo (sesión vacía, compositor
		 * centrado). Nunca tapa la tarjeta ni su botón de enviar.
		 */
		function placePanel() {
			const editor = composer();
			if (!panel) return;
			if (!editor || !editor.isConnected) {
				closePanel();
				return;
			}
			const rect = composerCard(editor).getBoundingClientRect();
			const viewportHeight = window.visualViewport?.height ?? window.innerHeight;
			const width = Math.min(Math.round(rect.width), window.innerWidth - 16);
			const left = Math.min(Math.max(8, Math.round(rect.left)), window.innerWidth - width - 8);
			panel.style.left = `${left}px`;
			panel.style.width = `${width}px`;
			const above = Math.min(rect.top, viewportHeight);
			const below = viewportHeight - rect.bottom;
			if (below > above) {
				panel.style.bottom = "";
				panel.style.top = `${Math.round(rect.bottom + 8)}px`;
				panel.style.maxHeight = `${Math.round(below - 16)}px`;
			} else {
				panel.style.top = "";
				panel.style.bottom = `${Math.round(window.innerHeight - rect.top + 8)}px`;
				panel.style.maxHeight = `${Math.round(above - 16)}px`;
			}
		}

		/** Líneas "- etiqueta: valor" con lo que quedó en el panel. */
		function correctionLines() {
			const lines = [];
			const push = (label, value) => {
				const clean = String(value || "").trim();
				if (clean) lines.push(`- ${label}: ${clean}`);
			};
			current.assumptions.forEach((item, index) => {
				const input = panel?.querySelector(`input[data-assumption="${index}"]`);
				push(item.label, input ? input.value : item.value);
			});
			current.missing.forEach((item, index) => {
				const input = panel?.querySelector(`input[data-missing="${index}"]`);
				push(item.label, input ? input.value : "");
			});
			return lines;
		}

		const textNode = (text) => ({ detail: 0, format: 0, mode: "normal", style: "", text, type: "text", version: 1 });
		const breakNode = () => ({ type: "linebreak", version: 1 });

		/**
		 * Agrega el bloque al final del compositor sin tocar lo que ya está (texto,
		 * chips de @archivos). Va por la instancia de Lexical: un execCommand o un
		 * paste sintético llegan con la selección de Lexical desfasada y se pierden.
		 * Los saltos son `linebreak`, lo mismo que deja Shift+Enter.
		 */
		function appendToComposer(lines) {
			const editor = composer();
			const lexical = editor?.__lexicalEditor;
			if (!lexical) return false;
			const before = draftText(editor);
			const state = lexical.getEditorState().toJSON();
			const block = [];
			for (const line of [HEADING, ...lines]) block.push(breakNode(), textNode(line));
			const root = state.root;
			const last = root.children[root.children.length - 1];
			if (last && last.type === "paragraph" && Array.isArray(last.children)) {
				last.children.push(breakNode(), ...block);
			} else {
				root.children.push({
					children: block.slice(1),
					direction: null,
					format: "",
					indent: 0,
					type: "paragraph",
					version: 1,
					textFormat: 0,
					textStyle: "",
				});
			}
			lexical.setEditorState(lexical.parseEditorState(state));
			lexical.focus(undefined, { defaultSelection: "rootEnd" });
			const after = draftText(editor);
			return after.startsWith(before) && after.includes(HEADING);
		}

		function render() {
			const editor = composer();
			if (!editor) return;
			if (current.assumptions.length === 0 && current.missing.length === 0) {
				closePanel();
				return;
			}
			closePanel();
			panel = document.createElement("div");
			panel.id = PANEL_ID;
			panel.setAttribute("role", "dialog");
			panel.setAttribute("aria-label", "Qué va a asumir el modelo");

			const rows = [];
			current.assumptions.forEach((item, index) => {
				rows.push(`
<div class="row">
  <label for="dsh-it-a${index}">${esc(item.label)}</label>
  <span class="val"><input class="mit" id="dsh-it-a${index}" data-assumption="${index}" value="${esc(item.value)}"></span>
</div>`);
			});
			current.missing.forEach((item, index) => {
				const chips = (item.options || [])
					.map((option) => `<button type="button" class="chip" data-for="${index}" title="${esc(option)}">${esc(option)}</button>`)
					.join("");
				rows.push(`
<div class="row">
  <label for="dsh-it-m${index}">${esc(item.label)}</label>
  <span class="val">
    ${chips}
    <input class="mit" id="dsh-it-m${index}" data-missing="${index}" placeholder="otra cosa…">
  </span>
</div>`);
			});

			panel.innerHTML = `
<header><strong>Qué va a asumir</strong><span class="hint">antes de enviar · Esc cierra</span></header>
<div class="body">${rows.join("")}</div>
<footer>
  <span class="note">se agrega al final del mensaje</span>
  <button type="button" class="btn" data-act="close">Descartar</button>
  <button type="button" class="btn primary" data-act="apply">Aplicar</button>
</footer>`;

			document.body.appendChild(panel);

			panel.addEventListener("click", (event) => {
				const chip = event.target.closest("button.chip");
				if (chip) {
					const input = panel.querySelector(`input[data-missing="${chip.dataset.for}"]`);
					const on = chip.getAttribute("data-on") !== "1";
					if (input) input.value = on ? chip.textContent : "";
					panel
						.querySelectorAll(`button.chip[data-for="${chip.dataset.for}"]`)
						.forEach((node) => node.setAttribute("data-on", on && node === chip ? "1" : "0"));
					return;
				}
				const action = event.target.closest("[data-act]")?.dataset.act;
				if (action === "close") {
					closePanel();
					return;
				}
				if (action === "apply") {
					const lines = correctionLines();
					if (lines.length === 0) {
						closePanel();
						return;
					}
					if (appendToComposer(lines)) {
						// Lo que acabamos de escribir no es un borrador nuevo para analizar.
						clearTimeout(timer);
						lastAnalyzed = draftText(composer());
						closePanel();
						return;
					}
					const note = panel.querySelector("footer .note");
					note.textContent = "no pude escribir en el compositor";
					note.setAttribute("data-error", "1");
				}
			});
			panel.addEventListener("input", (event) => {
				const missing = event.target.getAttribute?.("data-missing");
				if (missing === null || missing === undefined) return;
				panel
					.querySelectorAll(`button.chip[data-for="${missing}"]`)
					.forEach((node) => node.setAttribute("data-on", node.textContent === event.target.value ? "1" : "0"));
			});

			document.addEventListener("mousedown", onOutside, true);
			placePanel();
			if (typeof ResizeObserver === "function") {
				cardObserver = new ResizeObserver(placePanel);
				cardObserver.observe(composerCard(editor));
			}
		}

		/** El usuario ya tocó el panel: un análisis nuevo no le pisa lo que corrigió. */
		function panelInUse() {
			return !!panel && panel.contains(document.activeElement);
		}

		function analyze(text) {
			const mine = ++seq;
			inflight?.abort();
			inflight = new AbortController();
			fetch(ENDPOINT, {
				method: "POST",
				headers: { "content-type": "application/json", "x-dsh-intra-turn": "1" },
				body: JSON.stringify({ draft: text, sessionId: sessionIdOf() }),
				signal: inflight.signal,
			})
				.then((res) => res.json().then((data) => ({ ok: res.ok, data })))
				.then(({ ok, data }) => {
					if (!ok || mine !== seq) return;
					// Si ya se mandó o se borró el borrador, la respuesta llega tarde.
					if (draftText(composer()).length < MIN_CHARS) return;
					if (panelInUse()) return;
					current = {
						assumptions: Array.isArray(data.assumptions) ? data.assumptions : [],
						missing: Array.isArray(data.missing) ? data.missing : [],
					};
					render();
				})
				.catch(() => {});
		}

		/**
		 * Cualquier cambio del borrador. Lexical cancela `beforeinput` en pegar,
		 * autocompletar y dictado, y ahí no hay evento `input`; por eso se mira el
		 * DOM del editor con un MutationObserver.
		 */
		function schedule() {
			const editor = composer();
			if (!editor) return;
			const text = draftText(editor);
			clearTimeout(timer);
			if (text.length < MIN_CHARS) {
				seq++;
				inflight?.abort();
				closePanel();
				lastAnalyzed = "";
				return;
			}
			if (text === lastAnalyzed) return;
			timer = setTimeout(() => {
				const now = draftText(composer());
				if (now.length < MIN_CHARS || now === lastAnalyzed) return;
				lastAnalyzed = now;
				analyze(now);
			}, DEBOUNCE_MS);
		}

		/** Engancha el observer al editor actual (cambia al cambiar de sesión). */
		function observe() {
			const editor = composer();
			if (!editor || editor === observed) return;
			observer?.disconnect();
			observed = editor;
			observer = new MutationObserver(schedule);
			observer.observe(editor, { childList: true, subtree: true, characterData: true });
			if (panel) closePanel();
		}

		function onFocusIn(event) {
			const editor = composer();
			if (editor && editor.contains(event.target)) observe();
		}

		function onKey(event) {
			if (event.key !== "Escape" || !panel) return;
			event.stopPropagation();
			closePanel();
		}

		function apply() {
			injectStyles();
			document.addEventListener("focusin", onFocusIn, true);
			document.addEventListener("beforeinput", observe, true);
			document.addEventListener("keydown", onKey, true);
			window.addEventListener("resize", placePanel);
			window.visualViewport?.addEventListener("resize", placePanel);
			observe();
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	},
});
