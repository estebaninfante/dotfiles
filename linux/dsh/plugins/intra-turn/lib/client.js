/**
 * dsh-local-intra-turn — client half.
 *
 * Feedforward, tal cual la demo: mientras escribís, lo que el modelo va a
 * interpretar queda subrayado con puntos EN el borrador, arriba del compositor
 * aparece una línea por cada interpretación ("🗺️ Formato: itinerario día por
 * día"), y al pasar el mouse, tocar o llegar con el cursor a un subrayado cae
 * una tarjeta pegada a esa palabra con las preguntas de ese fragmento.
 *
 * El compositor del harness es Lexical (contenteditable), no un <textarea>:
 * se lee con innerText, los cambios se detectan con un MutationObserver y
 * "Aplicar" agrega nodos al estado de Lexical (ver appendToComposer). Los
 * subrayados son CSS Custom Highlights sobre Ranges: nada de nodos propios
 * adentro del editor, que Lexical reconcilia y rompería.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-intra-turn",
	factory: () => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const ENDPOINT = "/intra-turn/feedforward";
		const STYLE_ID = "dsh-intra-turn-style";
		const CARD_ID = "dsh-intra-turn-card";
		const SUMMARY_ID = "dsh-intra-turn-summary";
		const HL_MARK = "dsh-it-mark";
		const HL_DONE = "dsh-it-done";
		const HL_ACTIVE = "dsh-it-active";
		const DEBOUNCE_MS = 900;
		const MIN_CHARS = 12;
		const HOVER_CLOSE_MS = 280;
		const TYPING_QUIET_MS = 450;
		const NARROW_PX = 820;
		const HEADING = "Tené en cuenta:";

		let timer = null;
		let lastAnalyzed = "";
		let seq = 0;
		let inflight = null;
		let observed = null;
		let observer = null;
		let lastTyped = 0;

		/**
		 * Un ítem por interpretación o pregunta. `groups` junta los ítems que
		 * comparten fragmento: una tarjeta por fragmento, como "kids" en la demo.
		 */
		let items = [];
		let groups = [];
		/** Respuestas del usuario, por clave "quote|label": sobreviven a un análisis nuevo. */
		const answers = new Map();

		let card = null;
		let cardGroup = null;
		let cardAnchor = null;
		/** "hover" se cierra solo al salir; "pinned" espera Esc, click afuera o Aplicar. */
		let cardMode = "hover";
		let closeTimer = null;
		/** Cerrada a mano con el cursor adentro: no se reabre hasta que el cursor salga. */
		let dismissed = null;

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

		/** Tarjeta del compositor (texto + botones). */
		function composerCard(editor) {
			return editor?.closest("[data-composer-card]") ?? editor;
		}

		function sendButton(editor) {
			return composerCard(editor)?.querySelector('button[aria-label="Send message"], button[type="submit"]') ?? null;
		}

		/** Id de la sesión que se está mirando (lo escribe el renderer). */
		function sessionIdOf() {
			const scroll = document.querySelector("[data-conversation-scroll]");
			const host = scroll?.closest("[data-conversation-content]") ?? scroll?.parentElement;
			const id = host?.getAttribute("data-conversation-session");
			return typeof id === "string" && id.length > 0 ? id : "";
		}

		function draftText(node) {
			return String(node?.innerText ?? node?.textContent ?? "").replace(/ /g, " ").trim();
		}

		function injectStyles() {
			if (document.getElementById(STYLE_ID)) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = `
::highlight(${HL_MARK}){text-decoration:underline dotted 2px;text-underline-offset:5px;
  text-decoration-color:var(--dsw-alias-label-secondary,#cfd3d6)}
::highlight(${HL_DONE}){text-decoration:underline solid 2px;text-underline-offset:5px;
  text-decoration-color:var(--dsw-alias-state-business-primary,#6ea8fe)}
::highlight(${HL_ACTIVE}){background-color:var(--dsw-alias-interactive-bg-hover,#ffffff1f)}

#${SUMMARY_ID}{display:flex;flex-direction:column;gap:2px;padding:0 6px 8px;box-sizing:border-box;width:100%;min-width:0;max-width:100%;
  font:400 14px/1.6 var(--dsw-font-family,system-ui,sans-serif);color:var(--dsw-alias-label-tertiary,#adb2b8)}
#${SUMMARY_ID} .line{display:grid;grid-template-columns:1.4rem minmax(0,1fr) auto;align-items:baseline;gap:0 6px}
#${SUMMARY_ID} .emo{text-align:center}
#${SUMMARY_ID} .phrase{all:unset;cursor:pointer;border-radius:3px;color:var(--dsw-alias-label-secondary,#cfd3d6);
  text-decoration:underline dotted 1.5px;text-underline-offset:4px;text-decoration-color:var(--dsw-alias-label-caption,#81858c)}
#${SUMMARY_ID} .phrase:hover,#${SUMMARY_ID} .phrase[aria-expanded="true"]{background:var(--dsw-alias-interactive-bg-hover,#ffffff14)}
#${SUMMARY_ID} .phrase:focus-visible{outline:2px solid var(--dsw-alias-border-l4,#fff6);outline-offset:1px}
#${SUMMARY_ID} .phrase[data-edited="1"]{color:var(--dsw-alias-label-primary,#f9fafb);text-decoration-style:solid;
  text-decoration-color:var(--dsw-alias-state-business-primary,#6ea8fe)}
#${SUMMARY_ID} .acts{display:flex;justify-content:flex-end;gap:4px;align-self:center}
#${SUMMARY_ID} button.btn{height:26px;padding:0 10px}

#${CARD_ID}{position:absolute;z-index:1000;box-sizing:border-box;display:flex;flex-direction:column;
  border-radius:18px;background:var(--dsw-alias-bg-layer-2,#2c2c2e);color:var(--dsw-alias-label-primary,#f9fafb);
  box-shadow:0 0 0 .5px var(--dsw-alias-border-l2,#ffffff1f),0 12px 32px rgba(0,0,0,.35);
  font:400 13px/1.45 var(--dsw-font-family,system-ui,sans-serif);overflow:auto;animation:dsh-it-in .12s ease-out}
@keyframes dsh-it-in{from{opacity:0;transform:translateY(-3px)}}
#${CARD_ID}[data-side="top"]{animation-name:dsh-it-in-top}
@keyframes dsh-it-in-top{from{opacity:0;transform:translateY(3px)}}
#${CARD_ID} *{box-sizing:border-box}
#${CARD_ID} section{display:flex;flex-direction:column;gap:8px;padding:12px 14px 4px}
#${CARD_ID} .q{display:flex;align-items:baseline;gap:8px;color:var(--dsw-alias-label-tertiary,#adb2b8);font-size:13px}
#${CARD_ID} .q > span:first-child{flex:none;max-width:100%}
#${CARD_ID} .q .hint{color:var(--dsw-alias-label-caption,#81858c);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
#${CARD_ID} .q .now{margin-left:auto;color:var(--dsw-alias-label-primary,#f9fafb);font-weight:500;text-align:right;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:55%}
#${CARD_ID} .chips{display:flex;flex-wrap:wrap;gap:6px}
#${SUMMARY_ID} button.btn,#${CARD_ID} button.chip,#${CARD_ID} button.btn{height:30px;padding:0 12px;
  border:1px solid var(--dsw-alias-border-l2,#ffffff1f);border-radius:999px;background:transparent;
  color:var(--dsw-alias-label-secondary,#cfd3d6);font:inherit;font-size:12.5px;cursor:pointer;white-space:nowrap;
  max-width:100%;overflow:hidden;text-overflow:ellipsis}
#${CARD_ID} button.chip:hover,#${CARD_ID} button.btn:hover,#${SUMMARY_ID} button.btn:hover{
  background:var(--dsw-alias-interactive-bg-hover,#ffffff14);color:var(--dsw-alias-label-primary,#f9fafb)}
#${CARD_ID} button.chip[aria-pressed="true"]{background:var(--dsw-alias-label-primary,#f9fafb);
  border-color:transparent;color:var(--dsw-alias-label-primary-foreground,#0f1115)}
#${CARD_ID} button:focus-visible,#${SUMMARY_ID} button.btn:focus-visible{outline:2px solid var(--dsw-alias-border-l4,#fff6);outline-offset:1px}
#${CARD_ID} input.other{height:30px;padding:0 12px;min-width:0;width:100%;border:1px solid var(--dsw-alias-border-l2,#ffffff1f);
  border-radius:999px;background:var(--dsw-alias-bg-layer-1,#232324);color:inherit;font:inherit;font-size:12.5px;outline:none}
#${CARD_ID} input.other:focus{border-color:var(--dsw-alias-border-l4,#fff3)}
#${CARD_ID} input.other[hidden]{display:none}
#${CARD_ID} footer{display:flex;align-items:center;gap:6px;padding:10px 14px 12px}
#${CARD_ID} footer .note{flex:1;min-width:0;font-size:11.5px;color:var(--dsw-alias-label-caption,#81858c)}
#${CARD_ID} footer .note[data-error="1"]{color:var(--dsw-alias-state-error-primary,#f25a5a)}
#${CARD_ID} button.btn{border-color:transparent}
#${CARD_ID} button.btn.primary,#${SUMMARY_ID} button.btn.primary{background:var(--dsw-alias-button-primary-fill,#f9fafb);border-color:transparent;
  color:var(--dsw-alias-label-primary-foreground,#0f1115);font-weight:500}
#${CARD_ID} button.btn.primary:disabled{opacity:.4;cursor:default}
@media (max-width:${NARROW_PX}px){
  #${SUMMARY_ID} .line{grid-template-columns:1.4rem minmax(0,1fr)}
  #${SUMMARY_ID} .acts{grid-column:1 / -1}
  #${CARD_ID} footer .note{display:none}
  #${CARD_ID} button.chip{height:34px}
}
`;
			document.head.appendChild(style);
		}

		/* ---------------------------------------------------------------- ítems */

		const keyOf = (item) => `${item.quote}|${item.label}`;

		function answerOf(item) {
			let answer = answers.get(keyOf(item));
			if (!answer) {
				answer = item.kind === "assumption" ? { picked: [item.value], other: "" } : { picked: [], other: "" };
				answers.set(keyOf(item), answer);
			}
			return answer;
		}

		/** Lo que quedó elegido, en texto; "" si no hay nada. */
		function chosenText(item) {
			const answer = answerOf(item);
			const parts = [...answer.picked];
			if (answer.other.trim()) parts.push(answer.other.trim());
			return parts.join(", ");
		}

		/** ¿Hay algo para escribir en el mensaje? Confirmar lo que ya asumía no cuenta. */
		function isCorrection(item) {
			const text = chosenText(item);
			if (!text) return false;
			return item.kind === "assumption" ? text !== item.value : true;
		}

		function correctionLines() {
			return items.filter(isCorrection).map((item) => `- ${item.label.replace(/^¿|\?$/g, "")}: ${chosenText(item)}`);
		}

		function setItems(data) {
			const next = [];
			for (const a of Array.isArray(data.assumptions) ? data.assumptions : []) {
				if (a && typeof a.quote === "string" && a.quote) next.push({ kind: "assumption", quote: a.quote, label: a.label, value: a.value, options: a.options || [], emoji: a.emoji || "" });
			}
			for (const m of Array.isArray(data.missing) ? data.missing : []) {
				if (m && typeof m.quote === "string" && m.quote) next.push({ kind: "missing", quote: m.quote, label: m.label, options: m.options || [] });
			}
			items = next;
			const keys = new Set(items.map(keyOf));
			for (const key of [...answers.keys()]) if (!keys.has(key)) answers.delete(key);
			// "muy caro" adentro de "no sea muy caro": un solo subrayado, una sola tarjeta.
			const quotes = [...new Set(items.map((item) => item.quote))].sort((a, b) => b.length - a.length);
			const home = new Map();
			for (const quote of quotes) home.set(quote, quotes.find((outer) => outer.toLowerCase().includes(quote.toLowerCase())) ?? quote);
			const byQuote = new Map();
			for (const item of items) {
				const quote = home.get(item.quote);
				if (!byQuote.has(quote)) byQuote.set(quote, { quote, items: [], range: null });
				byQuote.get(quote).items.push(item);
			}
			groups = [...byQuote.values()];
		}

		function clearAll() {
			closeCard();
			items = [];
			groups = [];
			answers.clear();
			paintMarks();
			renderSummary();
		}

		/* ------------------------------------------------- fragmentos en el texto */

		/**
		 * Ubica cada fragmento en los nodos de texto del editor y le arma un Range.
		 * Se recalcula en cada mutación: Lexical reemplaza los nodos al tipear, y
		 * si el fragmento ya no está, el subrayado desaparece solo.
		 */
		function locateRanges() {
			const editor = composer();
			for (const group of groups) group.range = null;
			if (!editor || groups.length === 0) return;
			const nodes = [];
			let flat = "";
			const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);
			for (let node = walker.nextNode(); node; node = walker.nextNode()) {
				nodes.push({ node, start: flat.length });
				flat += node.data.replace(/ /g, " ");
			}
			const lower = flat.toLowerCase();
			const at = (offset) => {
				for (let i = nodes.length - 1; i >= 0; i--) if (offset >= nodes[i].start) return { node: nodes[i].node, offset: offset - nodes[i].start };
				return null;
			};
			for (const group of groups) {
				let index = flat.indexOf(group.quote);
				if (index < 0) index = lower.indexOf(group.quote.toLowerCase());
				if (index < 0) continue;
				const startPos = at(index);
				// El final se busca sobre el último carácter: así no salta al nodo siguiente.
				const endPos = at(index + group.quote.length - 1);
				if (!startPos || !endPos) continue;
				const range = document.createRange();
				range.setStart(startPos.node, startPos.offset);
				range.setEnd(endPos.node, endPos.offset + 1);
				group.range = range;
			}
		}

		function paintMarks() {
			const registry = globalThis.CSS?.highlights;
			if (registry === undefined || typeof globalThis.Highlight !== "function") return;
			const open = [];
			const done = [];
			for (const group of groups) {
				if (!group.range) continue;
				(group.items.some(isCorrection) ? done : open).push(group.range);
			}
			const set = (name, ranges) => (ranges.length > 0 ? registry.set(name, new globalThis.Highlight(...ranges)) : registry.delete(name));
			set(HL_MARK, open);
			set(HL_DONE, done);
			set(HL_ACTIVE, card && cardGroup?.range ? [cardGroup.range] : []);
		}

		function groupAtPoint(x, y) {
			for (const group of groups) {
				if (!group.range) continue;
				for (const rect of group.range.getClientRects()) {
					if (x >= rect.left - 2 && x <= rect.right + 2 && y >= rect.top - 3 && y <= rect.bottom + 5) return group;
				}
			}
			return null;
		}

		/** Fragmento donde está el cursor de texto (para abrir con teclado). */
		function groupAtCaret() {
			const selection = document.getSelection();
			if (!selection || selection.rangeCount === 0 || !selection.isCollapsed) return null;
			const caret = selection.getRangeAt(0);
			for (const group of groups) {
				if (!group.range) continue;
				const afterStart = group.range.compareBoundaryPoints(Range.START_TO_START, caret) <= 0;
				const beforeEnd = group.range.compareBoundaryPoints(Range.END_TO_END, caret) >= 0;
				if (afterStart && beforeEnd) return group;
			}
			return null;
		}

		/* -------------------------------------------- líneas arriba del compositor */

		function summaryPhrase(item) {
			const text = chosenText(item) || item.value;
			return `<button type="button" class="phrase" data-quote="${esc(item.quote)}" aria-haspopup="dialog" aria-expanded="false"${isCorrection(item) ? ' data-edited="1"' : ""}>${esc(text)}</button>`;
		}

		/**
		 * Una línea por interpretación, en el flujo, justo encima de la tarjeta del
		 * compositor (no flota sobre el chat). La frase subrayada abre la misma
		 * tarjeta que el fragmento del texto.
		 */
		function renderSummary() {
			const editor = composer();
			const host = composerCard(editor);
			let summary = document.getElementById(SUMMARY_ID);
			const lines = items.filter((item) => item.kind === "assumption" && groups.find((g) => g.quote === item.quote)?.range);
			const pending = correctionLines().length;
			if (!host || !host.parentElement || (lines.length === 0 && pending === 0)) {
				summary?.remove();
				return;
			}
			if (!summary) {
				summary = document.createElement("div");
				summary.id = SUMMARY_ID;
				summary.setAttribute("role", "list");
				summary.setAttribute("aria-label", "Qué va a interpretar el modelo");
				summary.addEventListener("click", onSummaryClick);
				summary.addEventListener("pointerover", onSummaryOver);
				summary.addEventListener("pointerout", onSummaryOut);
				summary.addEventListener("focusin", onSummaryFocus);
			}
			if (summary.parentElement !== host.parentElement || summary.nextElementSibling !== host) host.parentElement.insertBefore(summary, host);
			// Las acciones van en la última línea, no en una fila propia: aparecer no
			// corre el compositor (ni la tarjeta anclada a una palabra).
			const acts =
				pending > 0
					? `<span class="acts"><button type="button" class="btn" data-act="discard-all">Descartar</button><button type="button" class="btn primary" data-act="apply">Aplicar ${pending === 1 ? "1 corrección" : `${pending} correcciones`}</button></span>`
					: "<span></span>";
			const html =
				lines
					.map(
						(item, index) =>
							`<div class="line" role="listitem"><span class="emo" aria-hidden="true">${esc(item.emoji || "•")}</span><span>${esc(item.label)}: ${summaryPhrase(item)}</span>${index === lines.length - 1 ? acts : "<span></span>"}</div>`,
					)
					.join("") || `<div class="line"><span></span><span></span>${acts}</div>`;
			// Se llama en cada tecla: repintar sin cambios le quitaría el foco a una frase.
			if (summary.__html === html) return;
			summary.__html = html;
			summary.innerHTML = html;
			markExpanded();
			if (card) placeCard();
		}

		function markExpanded() {
			const open = card ? cardAnchor?.phraseQuote : undefined;
			document.querySelectorAll(`#${SUMMARY_ID} .phrase`).forEach((node) => node.setAttribute("aria-expanded", String(node.dataset.quote === open)));
		}

		function phraseGroup(node) {
			const phrase = node?.closest?.(".phrase");
			if (!phrase) return null;
			return { phrase, group: groups.find((g) => g.quote === phrase.dataset.quote) ?? null };
		}

		function onSummaryClick(event) {
			const action = event.target.closest("[data-act]")?.dataset.act;
			if (action === "apply") return applyCorrections(null);
			if (action === "discard-all") {
				answers.clear();
				closeCard();
				paintMarks();
				renderSummary();
				return;
			}
			const hit = phraseGroup(event.target);
			if (hit?.group) openCard(hit.group, phraseAnchor(hit.phrase), "pinned");
		}

		function onSummaryOver(event) {
			const hit = phraseGroup(event.target);
			if (!hit?.group) return;
			clearTimeout(closeTimer);
			if (card && cardMode === "pinned") return;
			openCard(hit.group, phraseAnchor(hit.phrase), "hover");
		}

		function onSummaryOut(event) {
			if (phraseGroup(event.target)) scheduleHoverClose();
		}

		function onSummaryFocus(event) {
			const hit = phraseGroup(event.target);
			if (hit?.group && event.target.matches(":focus-visible")) openCard(hit.group, phraseAnchor(hit.phrase), "pinned");
		}

		/** Ancla que sigue al nodo aunque el resumen se vuelva a pintar. */
		function phraseAnchor(phrase) {
			const quote = phrase.dataset.quote;
			return {
				phraseQuote: quote,
				rect: () => {
					const live = document.querySelector(`#${SUMMARY_ID} .phrase[data-quote="${CSS.escape(quote)}"]`);
					return live ? live.getBoundingClientRect() : null;
				},
			};
		}

		function rangeAnchor(group) {
			return {
				rect: () => {
					if (!group.range) return null;
					const rects = [...group.range.getClientRects()].filter((r) => r.width > 0);
					if (rects.length === 0) return null;
					// Arranca en la palabra y abarca todas sus líneas si el fragmento se parte.
					const top = Math.min(...rects.map((r) => r.top));
					const bottom = Math.max(...rects.map((r) => r.bottom));
					return { left: rects[0].left, right: rects[0].right, top, bottom, width: rects[0].width, height: bottom - top };
				},
			};
		}

		/* -------------------------------------------------- tarjeta del fragmento */

		function sectionHtml(item, index) {
			const answer = answerOf(item);
			const multi = item.kind === "missing";
			const choices = item.kind === "assumption" ? [item.value, ...item.options] : item.options;
			const chips = choices
				.map((choice) => `<button type="button" class="chip" data-item="${index}" data-choice="${esc(choice)}" aria-pressed="${answer.picked.includes(choice)}">${esc(choice)}</button>`)
				.join("");
			const other = answer.other;
			const label = item.kind === "assumption" ? `${item.emoji ? `${esc(item.emoji)} ` : ""}${esc(item.label)}` : esc(item.label);
			return `
<section data-item="${index}">
  <div class="q"><span>${label}</span>${multi ? '<span class="hint">elegí las que quieras</span>' : ""}${multi ? "" : `<span class="now" data-now="${index}">${esc(chosenText(item))}</span>`}</div>
  <div class="chips">${chips}<button type="button" class="chip" data-item="${index}" data-other="1" aria-expanded="${other ? "true" : "false"}">＋ Otra cosa</button></div>
  <input class="other" data-item="${index}" placeholder="${multi ? "Escribila…" : "Otra cosa…"}" value="${esc(other)}"${other ? "" : " hidden"} aria-label="${esc(item.label)}: otra respuesta">
</section>`;
		}

		function cardItems() {
			return cardGroup ? cardGroup.items : [];
		}

		function renderCard() {
			if (!card || !cardGroup) return;
			const pending = correctionLines().length;
			card.innerHTML =
				cardItems().map((item, index) => sectionHtml(item, index)).join("") +
				`<footer><span class="note">${pending > 0 ? "se agrega al final del mensaje" : "Esc cierra"}</span>` +
				`<button type="button" class="btn" data-act="discard">Descartar</button>` +
				`<button type="button" class="btn primary" data-act="apply"${pending > 0 ? "" : " disabled"}>Aplicar${pending > 1 ? ` ${pending}` : ""}</button></footer>`;
		}

		/** Refresca solo lo que cambió (no repinta la tarjeta: no se pierde el foco). */
		function refreshCardState() {
			if (!card) return;
			cardItems().forEach((item, index) => {
				const answer = answerOf(item);
				card.querySelectorAll(`button.chip[data-item="${index}"][data-choice]`).forEach((chip) => chip.setAttribute("aria-pressed", String(answer.picked.includes(chip.dataset.choice))));
				const now = card.querySelector(`[data-now="${index}"]`);
				if (now) now.textContent = chosenText(item);
			});
			const pending = correctionLines().length;
			const apply = card.querySelector('[data-act="apply"]');
			if (apply) {
				apply.disabled = pending === 0;
				apply.textContent = `Aplicar${pending > 1 ? ` ${pending}` : ""}`;
			}
			const note = card.querySelector("footer .note");
			if (note && note.getAttribute("data-error") !== "1") note.textContent = pending > 0 ? "se agrega al final del mensaje" : "Esc cierra";
			paintMarks();
			renderSummary();
		}

		function openCard(group, anchor, mode) {
			clearTimeout(closeTimer);
			if (card && cardGroup === group && cardAnchor?.phraseQuote === anchor.phraseQuote) {
				if (mode === "pinned") cardMode = "pinned";
				placeCard();
				return;
			}
			closeCard();
			cardGroup = group;
			cardAnchor = anchor;
			cardMode = mode;
			card = document.createElement("div");
			card.id = CARD_ID;
			card.setAttribute("role", "dialog");
			card.setAttribute("aria-label", `Sobre “${group.quote}”`);
			card.addEventListener("pointerdown", onCardPointerDown);
			card.addEventListener("click", onCardClick);
			card.addEventListener("input", onCardInput);
			card.addEventListener("keydown", onCardKey);
			card.addEventListener("pointerenter", () => clearTimeout(closeTimer));
			card.addEventListener("pointerleave", scheduleHoverClose);
			renderCard();
			document.body.appendChild(card);
			placeCard();
			paintMarks();
			markExpanded();
		}

		function closeCard() {
			clearTimeout(closeTimer);
			if (!card) return;
			const hadFocus = card.contains(document.activeElement);
			card.remove();
			card = null;
			cardGroup = null;
			cardAnchor = null;
			cardMode = "hover";
			paintMarks();
			markExpanded();
			if (hadFocus) composer()?.focus();
		}

		function scheduleHoverClose() {
			if (!card || cardMode !== "hover") return;
			clearTimeout(closeTimer);
			closeTimer = setTimeout(() => {
				if (card && cardMode === "hover" && !card.matches(":hover") && !card.contains(document.activeElement)) closeCard();
			}, HOVER_CLOSE_MS);
		}

		/**
		 * Debajo de la palabra, alineada con ella (como la demo). Si abajo no entra o
		 * taparía el botón de enviar, arriba. En pantallas angostas, ancho de
		 * pantalla. Va en coordenadas de página (position:absolute en el body):
		 * pegada al fragmento, no fija sobre el chat.
		 */
		function placeCard() {
			if (!card) return;
			const anchorRect = cardAnchor?.rect?.();
			const editor = composer();
			if (!anchorRect || !editor || !editor.isConnected) {
				closeCard();
				return;
			}
			const vw = document.documentElement.clientWidth || window.innerWidth;
			const vh = window.visualViewport?.height ?? window.innerHeight;
			const narrow = window.innerWidth <= NARROW_PX;
			const gap = 6;
			const margin = 8;
			const width = narrow ? vw - margin * 2 : Math.min(360, vw - margin * 2);
			card.style.width = `${width}px`;
			card.style.maxHeight = "";
			const left = narrow ? margin : Math.min(Math.max(margin, Math.round(anchorRect.left - 14)), vw - width - margin);
			const height = card.offsetHeight;
			const send = sendButton(editor)?.getBoundingClientRect();
			const overlapsSend = (top) =>
				!!send && send.width > 0 && left < send.right && left + width > send.left && top < send.bottom && top + height > send.top;
			const belowTop = anchorRect.bottom + gap;
			const spaceBelow = vh - belowTop - margin;
			const spaceAbove = anchorRect.top - gap - margin;
			let side;
			if (height <= spaceBelow && !overlapsSend(belowTop)) side = "bottom";
			else if (height <= spaceAbove) side = "top";
			else side = spaceBelow >= spaceAbove && !overlapsSend(belowTop) ? "bottom" : "top";
			const room = side === "bottom" ? spaceBelow : spaceAbove;
			const shown = Math.min(height, Math.max(120, room));
			if (shown < height) card.style.maxHeight = `${shown}px`;
			const top = side === "bottom" ? belowTop : anchorRect.top - gap - shown;
			card.dataset.side = side;
			card.style.left = `${Math.round(left + window.scrollX)}px`;
			card.style.top = `${Math.round(top + window.scrollY)}px`;
		}

		function onCardPointerDown(event) {
			// Botones: no le roban el foco al compositor (se sigue escribiendo igual).
			if (event.target.closest("button")) event.preventDefault();
			cardMode = "pinned";
		}

		function onCardClick(event) {
			const action = event.target.closest("[data-act]")?.dataset.act;
			if (action === "apply") return applyCorrections(card);
			if (action === "discard") {
				for (const item of cardItems()) answers.delete(keyOf(item));
				closeCard();
				paintMarks();
				renderSummary();
				return;
			}
			const chip = event.target.closest("button.chip");
			if (!chip) return;
			cardMode = "pinned";
			const index = Number(chip.dataset.item);
			const item = cardItems()[index];
			if (!item) return;
			const answer = answerOf(item);
			if (chip.dataset.other === "1") {
				const input = card.querySelector(`input.other[data-item="${index}"]`);
				input.hidden = false;
				chip.setAttribute("aria-expanded", "true");
				input.focus();
				placeCard();
				return;
			}
			const choice = chip.dataset.choice;
			if (item.kind === "missing") {
				answer.picked = answer.picked.includes(choice) ? answer.picked.filter((c) => c !== choice) : [...answer.picked, choice];
			} else {
				answer.picked = [choice];
				answer.other = "";
				const input = card.querySelector(`input.other[data-item="${index}"]`);
				if (input) input.value = "";
			}
			refreshCardState();
		}

		function onCardInput(event) {
			const input = event.target.closest("input.other");
			if (!input) return;
			const item = cardItems()[Number(input.dataset.item)];
			if (!item) return;
			const answer = answerOf(item);
			answer.other = input.value;
			// En una suposición, escribir otra cosa reemplaza la elegida.
			if (item.kind === "assumption") answer.picked = input.value.trim() ? [] : [item.value];
			refreshCardState();
		}

		function onCardKey(event) {
			if (event.key === "Enter" && event.target.matches("input.other")) {
				event.preventDefault();
				if (correctionLines().length > 0) applyCorrections(card);
			}
		}

		/* ------------------------------------------------------------- aplicar */

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

		function applyCorrections(from) {
			const lines = correctionLines();
			if (lines.length === 0) return;
			if (appendToComposer(lines)) {
				// Lo que acabamos de escribir no es un borrador nuevo para analizar.
				clearTimeout(timer);
				seq++;
				inflight?.abort();
				lastAnalyzed = draftText(composer());
				clearAll();
				return;
			}
			const note = from?.querySelector?.("footer .note");
			if (note) {
				note.textContent = "no pude escribir en el compositor";
				note.setAttribute("data-error", "1");
			}
		}

		/* --------------------------------------------------- análisis del borrador */

		/** El usuario está usando la tarjeta: un análisis nuevo no le pisa lo que corrigió. */
		function cardInUse() {
			return !!card && cardMode === "pinned";
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
					if (cardInUse()) return;
					closeCard();
					setItems(data);
					locateRanges();
					paintMarks();
					renderSummary();
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
			// Los subrayados siguen al texto: si el fragmento se borró, se van.
			locateRanges();
			paintMarks();
			renderSummary();
			if (card) placeCard();
			if (text.length < MIN_CHARS) {
				seq++;
				inflight?.abort();
				if (items.length > 0) clearAll();
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
			clearAll();
			lastAnalyzed = "";
		}

		/* ------------------------------------------------------- eventos globales */

		let moveFrame = 0;
		let lastPoint = null;

		/** Hover sobre el texto: los highlights no reciben eventos, se mide contra los rects. */
		function onPointerMove(event) {
			if (groups.length === 0 || event.pointerType === "touch") return;
			lastPoint = { x: event.clientX, y: event.clientY, target: event.target };
			if (moveFrame) return;
			moveFrame = requestAnimationFrame(() => {
				moveFrame = 0;
				const editor = composer();
				const point = lastPoint;
				if (!editor || !point) return;
				if (card && card.contains(point.target)) return;
				const inEditor = composerCard(editor).contains(point.target);
				const group = inEditor ? groupAtPoint(point.x, point.y) : null;
				if (group) {
					clearTimeout(closeTimer);
					if (!(card && cardMode === "pinned" && cardGroup !== group)) openCard(group, rangeAnchor(group), card && cardMode === "pinned" ? "pinned" : "hover");
				} else if (card && cardAnchor?.phraseQuote === undefined) {
					scheduleHoverClose();
				}
			});
		}

		/** Tocar (o clic) un subrayado lo deja abierto; tocar afuera cierra. */
		function onPointerDown(event) {
			const editor = composer();
			if (card && card.contains(event.target)) return;
			if (event.target.closest?.(`#${SUMMARY_ID}`)) return;
			const group = editor && editor.contains(event.target) ? groupAtPoint(event.clientX, event.clientY) : null;
			if (group) {
				dismissed = null;
				openCard(group, rangeAnchor(group), "pinned");
				return;
			}
			if (card) {
				dismissed = cardGroup;
				closeCard();
			}
		}

		/** Con teclado: el cursor quieto adentro de un fragmento abre su tarjeta. */
		function onSelectionChange() {
			const editor = composer();
			if (!editor || groups.length === 0 || document.activeElement !== editor) return;
			if (performance.now() - lastTyped < TYPING_QUIET_MS) return;
			const group = groupAtCaret();
			if (group !== dismissed) dismissed = null;
			if (group && group === dismissed) return;
			if (group) {
				if (!card || cardGroup !== group) openCard(group, rangeAnchor(group), "pinned");
			} else if (card && cardAnchor?.phraseQuote === undefined && !card.matches(":hover")) {
				closeCard();
			}
		}

		function onBeforeInput(event) {
			lastTyped = performance.now();
			observe(event);
		}

		function onFocusIn(event) {
			const editor = composer();
			if (editor && editor.contains(event.target)) observe();
		}

		function onKey(event) {
			if (event.key === "Escape" && card) {
				event.stopPropagation();
				event.preventDefault();
				dismissed = cardGroup;
				closeCard();
				return;
			}
			// Alt+↓ desde el compositor entra a la tarjeta abierta.
			if (event.key === "ArrowDown" && event.altKey && card && composer()?.contains(event.target)) {
				event.preventDefault();
				event.stopPropagation();
				cardMode = "pinned";
				card.querySelector("button.chip, input.other:not([hidden])")?.focus();
			}
		}

		function reposition() {
			if (card) placeCard();
		}

		function apply() {
			injectStyles();
			document.addEventListener("focusin", onFocusIn, true);
			document.addEventListener("beforeinput", onBeforeInput, true);
			document.addEventListener("keydown", onKey, true);
			document.addEventListener("pointermove", onPointerMove, { passive: true });
			document.addEventListener("pointerdown", onPointerDown, true);
			document.addEventListener("selectionchange", onSelectionChange);
			document.addEventListener("scroll", reposition, true);
			window.addEventListener("resize", reposition);
			window.visualViewport?.addEventListener("resize", reposition);
			observe();
		}

		exports.apply = apply;
		exports.inject = [];
		return module.exports;
	},
});
