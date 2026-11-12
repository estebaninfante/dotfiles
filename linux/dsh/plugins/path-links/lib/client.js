/**
 * dsh-local-path-links — client half.
 *
 * Las rutas escritas en el chat se vuelven tocables sin tocar el DOM de React:
 * el punto del mouse se convierte en un caret (`caretRangeFromPoint`), se lee
 * el token bajo el cursor y, si parece una ruta, se subraya con la API de
 * Highlights. Al hacer clic, el host resuelve `~`/relativas y stat: archivo →
 * panel lateral; carpeta → gestor de archivos; inexistente → aviso.
 */
window.__ModuleLoader__.load({
	id: "dsh-local-path-links",
	factory: () => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

		const ENDPOINT = "/path-links/open";
		const STYLE_ID = "dsh-path-links-style";
		const HIGHLIGHT_NAME = "dsh-path-hover";
		const HOVER_THROTTLE_MS = 90;
		const MAX_TOKEN_CHARS = 400;
		const FILE_EXTENSIONS = "md|markdown|txt|json|jsonl|ya?ml|toml|ini|cfg|conf|service|sh|bash|zsh|fish|py|js|mjs|cjs|ts|tsx|jsx|css|scss|sass|less|html?|vue|svelte|rs|go|rb|java|kt|swift|c|h|cc|cpp|hpp|cs|php|lua|pl|sql|db|sqlite|png|jpe?g|gif|webp|svg|ico|pdf|csv|tsv|xlsx?|docx?|pptx?|zip|tar|gz|tgz|log|lock|env|desktop|tmpl|template|patch|diff";

		const CSS = [
			"::highlight(" + HIGHLIGHT_NAME + "){text-decoration:underline dotted;text-underline-offset:2px;text-decoration-color:var(--dsw-alias-state-business-primary,#6ea8fe)}",
			".dsh-path-toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:2147483002;max-width:min(560px,calc(100vw - 32px));box-sizing:border-box;padding:9px 14px;border:1px solid var(--dsw-alias-border-l2,#3a3d42);border-radius:10px;background:var(--dsw-specific-input-major,#202226);color:var(--dsw-alias-label-primary,#e9e9ec);font:400 12px/1.4 system-ui,-apple-system,sans-serif;box-shadow:0 10px 30px #0009;white-space:pre-wrap;word-break:break-word}"
		].join("\n");

		let hoverTimer = 0;
		let hoverFrame = 0;
		let highlightRange = null;
		let toastTimer = 0;
		let toast = null;

		function ensureStyle() {
			if (document.getElementById(STYLE_ID) !== null) return;
			const style = document.createElement("style");
			style.id = STYLE_ID;
			style.textContent = CSS;
			document.head.appendChild(style);
		}

		function conversationScroll() {
			return document.querySelector("[data-conversation-scroll]");
		}

		function sessionIdOf() {
			const scroll = conversationScroll();
			const host = scroll?.closest("[data-conversation-content]") ?? scroll?.parentElement;
			const id = host?.getAttribute("data-conversation-session");
			return typeof id === "string" && id.length > 0 ? id : "";
		}

		/** Caret visual en un punto de la ventana (Chromium y estándar). */
		function caretAt(x, y) {
			if (typeof document.caretRangeFromPoint === "function") {
				const range = document.caretRangeFromPoint(x, y);
				return range === null ? void 0 : range;
			}
			if (typeof document.caretPositionFromPoint === "function") {
				const position = document.caretPositionFromPoint(x, y);
				if (position === null) return void 0;
				const range = document.createRange();
				range.setStart(position.offsetNode, position.offset);
				range.collapse(true);
				return range;
			}
			return void 0;
		}

		/** Token (sin espacios) alrededor del offset, con la puntuación de cierre fuera. */
		function tokenAt(text, offset) {
			let cursor = offset;
			if (cursor > 0 && cursor < text.length && /\s/.test(text[cursor]) && !/\s/.test(text[cursor - 1])) cursor -= 1;
			let start = cursor;
			let end = cursor;
			while (start > 0 && !/\s/.test(text[start - 1])) start -= 1;
			while (end < text.length && !/\s/.test(text[end])) end += 1;
			let token = text.slice(start, end);
			const lead = token.match(/^[("'`[{<]+/u);
			if (lead !== null) {
				start += lead[0].length;
				token = token.slice(lead[0].length);
			}
			const trail = token.match(/[)"'`\]}>.,;:!?]+$/u);
			if (trail !== null) {
				end -= trail[0].length;
				token = token.slice(0, token.length - trail[0].length);
			}
			return token.length > 0 ? { start, end, text: token } : void 0;
		}

		/** Heurística de ruta: con `/`, o nombre de archivo con extensión conocida. */
		function looksLikePath(token) {
			if (token.length < 3 || token.length > MAX_TOKEN_CHARS) return false;
			if (/^[a-z][a-z0-9+.-]*:\/\//iu.test(token)) return false;
			if (/^(?:https?|file|data|dsh-resource|mailto):/iu.test(token)) return false;
			if (token.startsWith("@") || token.startsWith("#") || token.startsWith("//")) return false;
			if (token.includes("\\")) return false;
			if (!token.includes("/")) return new RegExp(`\\.(?:${FILE_EXTENSIONS})$`, "iu").test(token);
			if (/^(?:~|\.{1,2}\/|\/)/u.test(token)) return true;
			if (token.endsWith("/")) return token.split("/").filter((part) => part.length > 0).length >= 1;
			return /^[\w.@+-]+\/[\w.@+./-]+$/u.test(token);
		}

		/** Ruta bajo el punto, solo dentro del transcript y fuera de controles. */
		function pathAtPoint(x, y) {
			const element = document.elementFromPoint(x, y);
			if (element === null) return void 0;
			if (element.closest("a, button, input, textarea, select, [contenteditable=\"true\"]") !== null) return void 0;
			if (element.closest("[data-conversation-scroll]") === null) return void 0;
			const range = caretAt(x, y);
			if (range === void 0) return void 0;
			const node = range.startContainer;
			if (node.nodeType !== 3) return void 0;
			const token = tokenAt(node.nodeValue ?? "", range.startOffset);
			if (token === void 0 || !looksLikePath(token.text)) return void 0;
			const target = document.createRange();
			target.setStart(node, token.start);
			target.setEnd(node, token.end);
			return { token: token.text, range: target };
		}

		function setHighlight(range) {
			if (typeof Highlight !== "function" || typeof CSS === "undefined" || CSS.highlights === void 0) return;
			highlightRange = range;
			CSS.highlights.set(HIGHLIGHT_NAME, new Highlight(range));
		}

		function clearHighlight() {
			highlightRange = null;
			if (typeof CSS !== "undefined" && CSS.highlights !== void 0) CSS.highlights.delete(HIGHLIGHT_NAME);
		}

		function showToast(message) {
			if (toast !== null) toast.remove();
			toast = document.createElement("div");
			toast.className = "dsh-path-toast";
			toast.textContent = message;
			document.body.appendChild(toast);
			window.clearTimeout(toastTimer);
			toastTimer = window.setTimeout(() => {
				toast?.remove();
				toast = null;
			}, 3200);
		}

		function onMouseMove(event) {
			window.clearTimeout(hoverTimer);
			const x = event.clientX;
			const y = event.clientY;
			hoverTimer = window.setTimeout(() => {
				if ((window.getSelection()?.toString() ?? "").length > 0) {
					clearHighlight();
					return;
				}
				const hit = pathAtPoint(x, y);
				if (hit === void 0) clearHighlight();
				else setHighlight(hit.range);
			}, HOVER_THROTTLE_MS);
		}

		function onMouseLeave() {
			window.clearTimeout(hoverTimer);
			clearHighlight();
		}

		async function openPath(raw) {
			try {
				const response = await fetch(ENDPOINT, {
					method: "POST",
					headers: {
						"content-type": "application/json",
						"x-dsh-path-links": "1"
					},
					credentials: "same-origin",
					body: JSON.stringify({ sessionId: sessionIdOf(), path: raw })
				});
				const payload = await response.json().catch(() => ({}));
				if (!response.ok) {
					showToast(`No pude abrir ${raw}: ${typeof payload.message === "string" ? payload.message : `error ${response.status}`}`);
					return;
				}
				if (payload.kind === "file") {
					const sidebar = ctxRef?.sidebarRight;
					if (sidebar === void 0 || typeof sidebar.openResource !== "function") {
						showToast("El panel lateral todavía no está disponible.");
						return;
					}
					sidebar.openResource(payload.address);
					return;
				}
				if (payload.kind === "dir") {
					if (payload.opened !== true) showToast(`No pude abrir la carpeta: ${payload.reason ?? "sin gestor"}`);
					return;
				}
				if (payload.kind === "missing") showToast(`No existe: ${payload.absolute ?? raw}`);
				else showToast(`No pude abrir ${raw}`);
			} catch (error) {
				showToast(`No pude abrir ${raw}: ${error instanceof Error ? error.message : String(error)}`);
			}
		}

		let ctxRef = null;

		function onClick(event) {
			if (event.defaultPrevented || event.button !== 0) return;
			if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
			if ((window.getSelection()?.toString() ?? "").length > 0) return;
			const hit = pathAtPoint(event.clientX, event.clientY);
			if (hit === void 0) return;
			event.preventDefault();
			event.stopPropagation();
			clearHighlight();
			void openPath(hit.token);
		}

		function onScroll() {
			clearHighlight();
		}

		function dispose() {
			document.removeEventListener("mousemove", onMouseMove, true);
			document.removeEventListener("mouseleave", onMouseLeave, true);
			document.removeEventListener("click", onClick, true);
			document.removeEventListener("scroll", onScroll, true);
			window.clearTimeout(hoverTimer);
			window.clearTimeout(toastTimer);
			clearHighlight();
			toast?.remove();
			toast = null;
			document.getElementById(STYLE_ID)?.remove();
		}

		function apply(ctx) {
			ctxRef = ctx;
			ensureStyle();
			document.addEventListener("mousemove", onMouseMove, true);
			document.addEventListener("mouseleave", onMouseLeave, true);
			document.addEventListener("click", onClick, true);
			document.addEventListener("scroll", onScroll, true);
			if (ctx !== void 0 && typeof ctx.effect === "function") ctx.effect(() => dispose, "path-links: clickable paths");
			return dispose;
		}

		exports.apply = apply;
		exports.inject = ["sidebarRight"];
		return module.exports;
	}
});
