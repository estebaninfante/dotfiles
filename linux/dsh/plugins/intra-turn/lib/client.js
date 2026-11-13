/**
 * dsh-local-intra-turn — client half.
 *
 * Feedforward, tal cual la demo: mientras escribís en el compositor, el modelo
 * dice qué va a asumir por vos y qué le falta saber, y vos lo corregís antes de
 * mandar.
 *
 * El compositor del harness es Lexical (contenteditable), no un <textarea>:
 * se lee con textContent y se reescribe seleccionando todo y usando
 * execCommand("insertText"), que Lexical escucha como entrada normal.
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

		let panel = null;
		let timer = null;
		let lastAnalyzed = "";
		let current = { assumptions: [], missing: [] };
		let busy = false;

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
			const direct = document.querySelector('[data-lexical-editor="true"]');
			if (direct) return direct;
			const editables = Array.from(document.querySelectorAll('div[contenteditable="true"]'));
			return editables.length > 0 ? editables[editables.length - 1] : null;
		}

		/** Id de la sesión que se está mirando (lo escribe el renderer). */
		function sessionIdOf() {
			const scroll = document.querySelector("[data-conversation-scroll]");
			const host = scroll?.closest("[data-conversation-content]") ?? scroll?.parentElement;
			const id = host?.getAttribute("data-conversation-session");
			return typeof id === "string" && id.length > 0 ? id : "";
		}

		function draftText(node) {
			return String(node?.innerText ?? node?.textContent ?? "").replace(/\u00a0/g, " ").trim();
		}

		function injectStyles() {
			if (document.getElementById(STYLE_ID)) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = `
#${PANEL_ID}{position:fixed;z-index:2147482500;width:min(560px,calc(100vw - 32px));
  border:1px solid var(--dsw-alias-border-l2,#2c2f36);border-radius:12px;background:#15171a;
  color:var(--dsw-alias-label-primary,#ecedef);box-shadow:0 18px 44px rgba(0,0,0,.55);
  font:400 13px/1.45 system-ui,-apple-system,sans-serif;overflow:hidden}
#${PANEL_ID} header{display:flex;align-items:center;gap:8px;padding:9px 12px;border-bottom:1px solid #23262b;
  background:#191c20;font-size:11px;letter-spacing:.05em;text-transform:uppercase;color:#8b9099;font-weight:600}
#${PANEL_ID} header .hint{margin-left:auto;text-transform:none;letter-spacing:0;font-weight:400;font-size:11px;color:#6d727b}
#${PANEL_ID} .body{padding:8px 12px 10px;display:flex;flex-direction:column;gap:8px;max-height:44vh;overflow:auto}
#${PANEL_ID} .row{display:flex;align-items:center;gap:8px}
#${PANEL_ID} .row > label{flex:none;width:132px;color:#8b9099;font-size:11.5px;text-align:right}
#${PANEL_ID} .val{flex:1;min-width:0;display:flex;align-items:center;gap:6px;flex-wrap:wrap}
#${PANEL_ID} input.mit{flex:1;min-width:80px;height:28px;padding:0 8px;border:1px solid #33363c;border-radius:7px;
  background:#0f1114;color:inherit;font:inherit;font-size:12.5px;outline:none}
#${PANEL_ID} input.mit:focus{border-color:#4c8dff}
#${PANEL_ID} button.chip{height:26px;padding:0 9px;border:1px solid #33363c;border-radius:999px;background:transparent;
  color:#b9bdc6;font:inherit;font-size:12px;cursor:pointer}
#${PANEL_ID} button.chip:hover{background:#1f2228;color:#ecedef}
#${PANEL_ID} button.chip[data-on="1"]{background:#22304a;border-color:#3d5b8f;color:#dbe6f7}
#${PANEL_ID} footer{display:flex;align-items:center;gap:8px;padding:9px 12px;border-top:1px solid #23262b;background:#191c20}
#${PANEL_ID} footer .grow{flex:1}
#${PANEL_ID} button.btn{height:28px;padding:0 11px;border:1px solid #33363c;border-radius:8px;background:transparent;
  color:#b9bdc6;font:inherit;font-size:12.5px;cursor:pointer}
#${PANEL_ID} button.btn:hover{background:#1f2228;color:#ecedef}
#${PANEL_ID} button.btn.primary{background:#ecedef;border-color:transparent;color:#141518;font-weight:500}
#${PANEL_ID} button.btn.primary:hover{background:#fff}
#${PANEL_ID} button.btn[disabled]{opacity:.45;cursor:default}
#${PANEL_ID} .empty{color:#8b9099;font-size:12px}
`;
			document.head.appendChild(style);
		}

		function closePanel() {
			if (panel) panel.remove();
			panel = null;
			document.removeEventListener("mousedown", onOutside, true);
		}

		function onOutside(event) {
			if (!panel) return;
			if (panel.contains(event.target)) return;
			const editor = composer();
			if (editor && editor.contains(event.target)) return;
			closePanel();
		}

		function placePanel() {
			const editor = composer();
			if (!panel || !editor) return;
			const rect = editor.getBoundingClientRect();
			panel.style.left = `${Math.max(12, Math.round(rect.left))}px`;
			panel.style.top = `${Math.max(12, Math.round(rect.top - panel.offsetHeight - 10))}px`;
			panel.style.width = `${Math.min(560, Math.max(320, Math.round(rect.width)))}px`;
		}

		/** Texto final que se escribe en el compositor al aplicar. */
		function composedText(draft) {
			const lines = [];
			const push = (label, value) => {
				const clean = String(value || "").trim();
				if (clean) lines.push(`${label}: ${clean}`);
			};
			for (const item of current.assumptions) {
				const input = panel?.querySelector(`input[data-assumption="${item.label}"]`);
				push(item.label, input ? input.value : item.value);
			}
			for (const item of current.missing) {
				const input = panel?.querySelector(`input[data-missing="${item.label}"]`);
				push(item.label, input ? input.value : "");
			}
			if (lines.length === 0) return draft;
			return `${draft}\n\nTené en cuenta:\n${lines.map((l) => `- ${l}`).join("\n")}`;
		}

		/** Reescribe el compositor (Lexical) con el texto nuevo. */
		function writeComposer(text) {
			const editor = composer();
			if (!editor) return false;
			editor.focus();
			const range = document.createRange();
			range.selectNodeContents(editor);
			const selection = window.getSelection();
			if (selection) {
				selection.removeAllRanges();
				selection.addRange(range);
			}
			let ok = false;
			try {
				ok = document.execCommand("insertText", false, text);
			} catch {
				ok = false;
			}
			if (!ok) {
				try {
					const data = new DataTransfer();
					data.setData("text/plain", text);
					editor.dispatchEvent(
						new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }),
					);
					ok = true;
				} catch {
					ok = false;
				}
			}
			return ok;
		}

		function render() {
			const editor = composer();
			if (!editor) return;
			if (current.assumptions.length === 0 && current.missing.length === 0) {
				closePanel();
				return;
			}
			document.removeEventListener("mousedown", onOutside, true);
			if (panel) panel.remove();
			panel = document.createElement("div");
			panel.id = PANEL_ID;

			const rows = [];
			for (const item of current.assumptions) {
				rows.push(`
<div class="row">
  <label>${esc(item.label)}</label>
  <span class="val"><input class="mit" data-assumption="${esc(item.label)}" value="${esc(item.value)}"></span>
</div>`);
			}
			for (const item of current.missing) {
				const chips = (item.options || [])
					.map((option) => `<button type="button" class="chip" data-opt="${esc(option)}" data-for="${esc(item.label)}">${esc(option)}</button>`)
					.join("");
				rows.push(`
<div class="row">
  <label>${esc(item.label)}</label>
  <span class="val">
    ${chips}
    <input class="mit" data-missing="${esc(item.label)}" placeholder="otra cosa…">
  </span>
</div>`);
			}

			panel.innerHTML = `
<header>Feedforward <span class="hint">antes de enviar · Esc cierra</span></header>
<div class="body">${rows.join("") || '<div class="empty">Nada que asumir.</div>'}</div>
<footer>
  <span class="grow" style="font-size:11px;color:#6d727b">se agrega al mensaje, no lo reemplaza</span>
  <button type="button" class="btn" data-act="close">Descartar</button>
  <button type="button" class="btn primary" data-act="apply">Aplicar</button>
</footer>`;

			document.body.appendChild(panel);

			panel.addEventListener("click", (event) => {
				const chip = event.target.closest("button.chip");
				if (chip) {
					const input = panel.querySelector(`input[data-missing="${chip.dataset.for}"]`);
					if (input) input.value = chip.dataset.opt;
					panel
						.querySelectorAll(`button.chip[data-for="${chip.dataset.for}"]`)
						.forEach((node) => node.setAttribute("data-on", node === chip ? "1" : "0"));
					return;
				}
				const action = event.target.closest("[data-act]")?.dataset.act;
				if (action === "close") {
					closePanel();
					return;
				}
				if (action === "apply" && !busy) {
					const draft = draftText(composer());
					const next = composedText(draft);
					if (writeComposer(next)) closePanel();
				}
			});

			document.addEventListener("mousedown", onOutside, true);
			placePanel();
		}

		function analyze(text) {
			if (busy) return;
			busy = true;
			fetch(ENDPOINT, {
				method: "POST",
				headers: { "content-type": "application/json", "x-dsh-intra-turn": "1" },
				body: JSON.stringify({ draft: text, sessionId: sessionIdOf() }),
			})
				.then((res) => res.json().then((data) => ({ ok: res.ok, data })))
				.then(({ ok, data }) => {
					if (!ok) return;
					current = {
						assumptions: Array.isArray(data.assumptions) ? data.assumptions : [],
						missing: Array.isArray(data.missing) ? data.missing : [],
					};
					render();
				})
				.catch(() => {})
				.finally(() => {
					busy = false;
				});
		}

		function onInput(event) {
			const editor = composer();
			if (!editor || !(event.target === editor || editor.contains(event.target))) return;
			const text = draftText(editor);
			clearTimeout(timer);
			if (text.length < MIN_CHARS) {
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

		function onKey(event) {
			if (event.key !== "Escape" || !panel) return;
			event.stopPropagation();
			closePanel();
		}

		function apply() {
			injectStyles();
			document.addEventListener("input", onInput, true);
			document.addEventListener("keydown", onKey, true);
			window.addEventListener("resize", placePanel);
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	},
});
