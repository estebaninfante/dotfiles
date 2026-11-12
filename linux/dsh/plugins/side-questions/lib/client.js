/**
 * dsh-local-side-questions — client half.
 *
 * Seleccionás texto en la conversación, aparece un botón "Preguntar" pegado a
 * la selección y la respuesta llega a un globo flotante. Nada de esto entra
 * en el transcript: la pregunta viaja directo a /side-questions/ask y la
 * respuesta se queda en el globo.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-side-questions",
	factory: () => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const ENDPOINT = "/side-questions/ask";
		const STYLE_ID = "dsh-side-questions-style";
		const MIN_QUOTE_CHARS = 3;
		const PANEL_WIDTH = 360;
		const MARGIN = 8;

		const CSS = [
			".dsh-sideq-bubble{position:fixed;z-index:2147483000;display:inline-flex;align-items:center;gap:6px;height:30px;padding:0 11px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:999px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#e9e9ec);font:500 12px/1 system-ui,-apple-system,sans-serif;box-shadow:0 8px 24px #0009;cursor:pointer;user-select:none}",
			".dsh-sideq-bubble:hover{background:var(--dsw-alias-interactive-bg-hover,#2a2d33)}",
			".dsh-sideq-bubble svg{width:13px;height:13px;flex:none}",
			".dsh-sideq-panel{position:fixed;z-index:2147483001;box-sizing:border-box;width:" + PANEL_WIDTH + "px;max-width:calc(100vw - 16px);display:flex;flex-direction:column;gap:8px;padding:12px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:14px;background:var(--dsw-specific-input-major,#1c1e22);color:var(--dsw-alias-label-primary,#e9e9ec);font:400 13px/1.45 system-ui,-apple-system,sans-serif;box-shadow:0 18px 50px #000000b3}",
			".dsh-sideq-head{display:flex;align-items:center;justify-content:space-between;gap:8px}",
			".dsh-sideq-title{font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#8b8f98)}",
			".dsh-sideq-close{width:22px;height:22px;display:grid;place-items:center;border:0;border-radius:999px;background:transparent;color:inherit;cursor:pointer;font-size:16px;line-height:1;padding:0}",
			".dsh-sideq-close:hover{background:var(--dsw-alias-interactive-bg-hover,#2a2d33)}",
			".dsh-sideq-quote{margin:0;padding:7px 9px;border-radius:8px;background:var(--dsw-alias-bg-overlay,#24262b);color:var(--dsw-alias-label-secondary,#b9bdc6);font-size:12px;line-height:1.4;max-height:84px;overflow:auto;white-space:pre-wrap;word-break:break-word}",
			".dsh-sideq-input{box-sizing:border-box;width:100%;min-height:56px;max-height:140px;resize:vertical;padding:8px 9px;border:1px solid var(--dsw-alias-border-l3,#33363c);border-radius:9px;background:transparent;color:inherit;font:inherit;outline:none}",
			".dsh-sideq-input:focus{border-color:var(--dsw-alias-state-business-primary,#4c8dff)}",
			".dsh-sideq-actions{display:flex;align-items:center;justify-content:space-between;gap:8px}",
			".dsh-sideq-hint{font-size:11px;color:var(--dsw-alias-label-caption,#767b85)}",
			".dsh-sideq-submit{height:28px;padding:0 12px;border:0;border-radius:8px;background:var(--dsw-alias-label-primary,#e9e9ec);color:var(--dsw-alias-label-primary-foreground,#141518);font:600 12px/1 system-ui,-apple-system,sans-serif;cursor:pointer}",
			".dsh-sideq-submit:disabled{opacity:.5;cursor:default}",
			".dsh-sideq-answer{display:none;padding-top:2px;border-top:1px solid var(--dsw-alias-border-l3,#33363c);font-size:13px;line-height:1.5;max-height:40vh;overflow:auto;white-space:pre-wrap;word-break:break-word}",
			".dsh-sideq-answer[data-open=\"1\"]{display:block;margin-top:4px}",
			".dsh-sideq-answer[data-error=\"1\"]{color:var(--dsw-alias-state-error-primary,#ff6b6b)}",
			".dsh-sideq-dots:after{content:\"…\";animation:dsh-sideq-pulse 1.2s ease-in-out infinite}",
			"@keyframes dsh-sideq-pulse{0%,100%{opacity:.35}50%{opacity:1}}"
		].join("\n");

		let bubble = null;
		let panel = null;
		let panelQuote = "";
		let bubbleQuote = "";

		function ensureStyle() {
			if (document.getElementById(STYLE_ID) !== null) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = CSS;
			document.head.appendChild(style);
		}

		/** Contenedor scrolleable de la conversación visible. */
		function conversationScroll() {
			return document.querySelector("[data-conversation-scroll]");
		}

		/** Id de la sesión que se está mirando (lo escribe el renderer). */
		function sessionIdOf() {
			const scroll = conversationScroll();
			const host = scroll?.closest("[data-conversation-content]") ?? scroll?.parentElement;
			const id = host?.getAttribute("data-conversation-session");
			return typeof id === "string" && id.length > 0 ? id : "";
		}

		/** Extracto del final de la conversación: lo cercano a la pregunta. */
		function transcriptTail(limit) {
			const scroll = conversationScroll();
			if (scroll === null) return "";
			const text = String(scroll.innerText ?? "").replace(/\n{3,}/g, "\n\n").trim();
			return text.length > limit ? text.slice(text.length - limit) : text;
		}

		function clamp(value, min, max) {
			return Math.max(min, Math.min(value, max));
		}

		function paragraph(text) {
			const node = document.createElement("p");
			node.textContent = text;
			return node;
		}

		/** Botón flotante pegado a la selección. */
		function showBubble(rect, quote) {
			bubbleQuote = quote;
			if (bubble === null) {
				bubble = document.createElement("button");
				bubble.type = "button";
				bubble.className = "dsh-sideq-bubble";
				bubble.setAttribute("aria-label", "Preguntar sobre el texto seleccionado");
				bubble.textContent = "Preguntar";
				bubble.addEventListener("mousedown", (event) => {
					event.preventDefault();
					event.stopPropagation();
				});
				bubble.addEventListener("click", (event) => {
					event.preventDefault();
					event.stopPropagation();
					const quote = bubbleQuote;
					const anchor = rect;
					hideBubble();
					openPanel(quote, anchor);
				});
				document.body.appendChild(bubble);
			}
			bubble.style.visibility = "hidden";
			bubble.style.top = "0px";
			bubble.style.left = "0px";
			const width = bubble.offsetWidth;
			const height = bubble.offsetHeight;
			// Pegado al final de la última línea seleccionada, centrado verticalmente;
			// si no entra a la derecha, debajo a la izquierda.
			const right = rect.right + 8;
			const top = rect.top + (rect.height - height) / 2;
			if (right + width <= window.innerWidth - MARGIN) {
				bubble.style.left = `${right}px`;
				bubble.style.top = `${clamp(top, MARGIN, window.innerHeight - height - MARGIN)}px`;
			} else {
				bubble.style.left = `${clamp(rect.left, MARGIN, window.innerWidth - width - MARGIN)}px`;
				bubble.style.top = `${clamp(rect.bottom + 6, MARGIN, window.innerHeight - height - MARGIN)}px`;
			}
			bubble.style.visibility = "visible";
		}

		function hideBubble() {
			if (bubble === null) return;
			bubble.remove();
			bubble = null;
		}

		/** Globo con la cita, la pregunta y la respuesta. */
		function openPanel(quote, rect) {
			closePanel();
			panelQuote = quote;
			panel = document.createElement("div");
			panel.className = "dsh-sideq-panel";
			panel.setAttribute("role", "dialog");
			panel.setAttribute("aria-label", "Pregunta lateral");

			const head = document.createElement("div");
			head.className = "dsh-sideq-head";
			const title = document.createElement("span");
			title.className = "dsh-sideq-title";
			title.textContent = "Pregunta lateral";
			const close = document.createElement("button");
			close.type = "button";
			close.className = "dsh-sideq-close";
			close.setAttribute("aria-label", "Cerrar");
			close.textContent = "×";
			close.addEventListener("click", closePanel);
			head.append(title, close);

			const blockquote = document.createElement("blockquote");
			blockquote.className = "dsh-sideq-quote";
			blockquote.textContent = quote;

			const input = document.createElement("textarea");
			input.className = "dsh-sideq-input";
			input.rows = 2;
			input.placeholder = "Preguntá sobre esto…";

			const actions = document.createElement("div");
			actions.className = "dsh-sideq-actions";
			const hint = document.createElement("span");
			hint.className = "dsh-sideq-hint";
			hint.textContent = "Enter envía · Esc cierra";
			const submit = document.createElement("button");
			submit.type = "button";
			submit.className = "dsh-sideq-submit";
			submit.textContent = "Preguntar";
			actions.append(hint, submit);

			const answer = document.createElement("div");
			answer.className = "dsh-sideq-answer";

			const run = () => {
				const question = input.value.trim();
				if (question.length === 0 || submit.disabled) return;
				void ask(question, { input, submit, answer });
			};
			submit.addEventListener("click", run);
			input.addEventListener("keydown", (event) => {
				if (event.key !== "Enter" || event.shiftKey) return;
				event.preventDefault();
				run();
			});

			panel.append(head, blockquote, input, actions, answer);
			document.body.appendChild(panel);

			panel.style.visibility = "hidden";
			panel.style.top = "0px";
			panel.style.left = "0px";
			const height = panel.offsetHeight;
			const left = clamp(rect.left, MARGIN, window.innerWidth - PANEL_WIDTH - MARGIN);
			const below = rect.bottom + 10;
			panel.style.top = `${below + height <= window.innerHeight - MARGIN ? below : clamp(rect.top - height - 10, MARGIN, window.innerHeight - height - MARGIN)}px`;
			panel.style.left = `${left}px`;
			panel.style.visibility = "visible";
			window.setTimeout(() => {
				input.focus();
			}, 0);
		}

		function closePanel() {
			if (panel === null) return;
			panel.remove();
			panel = null;
			panelQuote = "";
		}

		/** Pide la respuesta al host. No toca la sesión. */
		async function ask(question, ui) {
			ui.submit.disabled = true;
			ui.answer.dataset.open = "1";
			ui.answer.dataset.error = "0";
			ui.answer.replaceChildren(paragraph("Pensando"));
			ui.answer.firstElementChild.className = "dsh-sideq-dots";
			try {
				const response = await fetch(ENDPOINT, {
					method: "POST",
					headers: {
						"content-type": "application/json",
						"x-dsh-side-question": "1"
					},
					credentials: "same-origin",
					body: JSON.stringify({
						sessionId: sessionIdOf(),
						quote: panelQuote,
						question,
						transcript: transcriptTail(14000)
					})
				});
				const payload = await response.json().catch(() => ({}));
				if (!response.ok) throw new Error(typeof payload.message === "string" ? payload.message : `error ${response.status}`);
				ui.answer.dataset.error = "0";
				ui.answer.replaceChildren(paragraph(typeof payload.answer === "string" ? payload.answer : "(respuesta vacía)"));
			} catch (error) {
				ui.answer.dataset.error = "1";
				ui.answer.replaceChildren(paragraph(`No pude responder: ${error instanceof Error ? error.message : String(error)}`));
			} finally {
				ui.submit.disabled = false;
			}
		}

		/** Selección válida (dentro de la conversación, no en un campo de texto). */
		function currentSelection() {
			const selection = window.getSelection();
			if (selection === null || selection.isCollapsed || selection.rangeCount === 0) return void 0;
			const text = selection.toString().trim();
			if (text.length < MIN_QUOTE_CHARS) return void 0;
			const range = selection.getRangeAt(0);
			const node = range.commonAncestorContainer;
			const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
			if (element === null) return void 0;
			if (element.closest("[data-conversation-scroll]") === null) return void 0;
			if (element.closest("textarea, input, [contenteditable=\"true\"]") !== null) return void 0;
			const rects = range.getClientRects();
			const bounding = range.getBoundingClientRect();
			const lastRect = rects.length > 0 ? rects[rects.length - 1] : bounding;
			if (bounding.width === 0 && bounding.height === 0) return void 0;
			return { text, rect: bounding, lastRect };
		}

		function onMouseUp(event) {
			if (panel !== null && event.target instanceof Node && panel.contains(event.target)) return;
			if (bubble !== null && event.target instanceof Node && bubble.contains(event.target)) return;
			const selection = currentSelection();
			if (selection === void 0) {
				hideBubble();
				return;
			}
			showBubble(selection.lastRect, selection.text);
		}

		function onMouseDown(event) {
			if (panel !== null && event.target instanceof Node && panel.contains(event.target)) return;
			if (bubble !== null && event.target instanceof Node && bubble.contains(event.target)) return;
			hideBubble();
		}

		function onKeyDown(event) {
			if (event.key !== "Escape") return;
			if (panel === null) return;
			event.stopPropagation();
			closePanel();
		}

		function onScroll() {
			hideBubble();
		}

		function dispose() {
			document.removeEventListener("mouseup", onMouseUp, true);
			document.removeEventListener("mousedown", onMouseDown, true);
			document.removeEventListener("keydown", onKeyDown, true);
			document.removeEventListener("scroll", onScroll, true);
			window.removeEventListener("resize", hideBubble);
			hideBubble();
			closePanel();
			document.getElementById(STYLE_ID)?.remove();
		}

		function apply(ctx) {
			ensureStyle();
			document.addEventListener("mouseup", onMouseUp, true);
			document.addEventListener("mousedown", onMouseDown, true);
			document.addEventListener("keydown", onKeyDown, true);
			document.addEventListener("scroll", onScroll, true);
			window.addEventListener("resize", hideBubble);
			if (ctx !== void 0 && typeof ctx.effect === "function") ctx.effect(() => dispose, "side-questions: selection bubble");
			return dispose;
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	}
});
