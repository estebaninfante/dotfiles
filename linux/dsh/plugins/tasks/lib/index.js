/**
 * dsh-local-tasks — host half.
 *
 * Tareas por proyecto (carpeta) y evidencia real de cada conversación tomada del
 * log de la sesión (`ctx.sessionQuery`), no de lo que el agente dice.
 *
 * Cada pedido del usuario queda registrado como tarea: al llegar su mensaje
 * dentro de un turno se crea la tarea del proyecto, y un guard impide que el
 * agente actúe mientras esa tarea no exista. Las rutas HTTP viven en routes.js.
 */
import { firstLine, rootSession, textOfMessage } from "./events.js";
import { registerRoutes } from "./routes.js";
import { adoptTurn, createTask, findSessionTask, findTurnTask, updateTask } from "./store.js";

export const inject = ["webServer", "sessionQuery", "systemPrompt", "tools"];

export function apply(ctx) {
	// Estado en vivo de los pedidos: turno actual, cierre y registro en curso.
	const live = {
		currentTurn: new Map(),
		turnEnds: new Map(),
		running: new Set(),
		registering: new Map(),
		inflight: new Map(),
		requestText: new Map(),
	};
	registerRoutes(ctx, live);

	// Un turno = una tarea. Solo cuentan los mensajes con source.kind "user":
	// los recordatorios y el runtime context del harness también llegan como
	// user/message y no son pedidos.
	async function registerRequest(session) {
		const sessionId = session.id;
		const turn = live.currentTurn.get(sessionId);
		const request = live.requestText.get(sessionId) ?? "";
		if (!turn || !request) return;
		if ((await findTurnTask(sessionId, turn)) !== null) return;
		const linked = await findSessionTask(sessionId);
		if (linked !== null && linked.turn == null) {
			await adoptTurn(sessionId, turn);
			return;
		}
		const title = firstLine(request) || `Pedido del turno ${turn}`;
		await createTask({
			workspace: session.header.cwd,
			title,
			sessionId,
			turn,
			origin: "auto",
		});
	}
	function scheduleRegister(session) {
		const sessionId = session.id;
		if (live.inflight.has(sessionId)) return;
		live.registering.set(sessionId, { at: Date.now() });
		const job = registerRequest(session)
			.catch(() => undefined)
			.finally(() => {
				live.inflight.delete(sessionId);
				live.registering.delete(sessionId);
				live.requestText.delete(sessionId);
			});
		live.inflight.set(sessionId, job);
	}
	ctx.on("session/event", (session, event) => {
		if (!rootSession(session)) return;
		if (event.type === "turn/start") {
			const turn = Number(event.data?.turn ?? 0);
			if (!Number.isSafeInteger(turn) || turn <= 0) return;
			live.currentTurn.set(session.id, turn);
			live.running.add(session.id);
			if (live.requestText.has(session.id)) scheduleRegister(session);
			return;
		}
		if (event.type === "turn/end") {
			const turn = Number(event.data?.turn ?? 0);
			const reason = String(event.data?.reason?.kind ?? "?");
			live.running.delete(session.id);
			if (Number.isSafeInteger(turn) && turn > 0) {
				live.turnEnds.set(session.id, { turn, reason });
				findTurnTask(session.id, turn)
					.then((task) => (task ? updateTask(task.id, { closeReason: reason, closedAt: Date.now() }) : null))
					.catch(() => undefined);
			}
			return;
		}
		if (event.type !== "user/message") return;
		if (event.data?.source?.kind !== "user") return;
		const text = textOfMessage(event.data);
		if (!text) return;
		live.requestText.set(session.id, text);
		if (live.currentTurn.has(session.id)) scheduleRegister(session);
	});
	ctx.effect(
		() =>
			ctx.tools.guard((execution) => {
				const sessionId = execution?.agent?.id;
				if (!sessionId) return undefined;
				const state = live.registering.get(sessionId);
				if (!state) return undefined;
				if (Date.now() - state.at > 8000) return undefined;
				if (execution.name === "ask_user_question") return undefined;
				return "El harness está registrando este pedido como tarea del proyecto. Reintentá la misma llamada en un instante.";
			}),
		"tasks: cada pedido necesita tarea",
	);

	ctx.effect(
		() =>
			ctx.systemPrompt.section({
				name: "local-tasks/evidence",
				order: 45,
				text: [
					"## Tareas y evidencia",
					"Cada pedido del usuario queda registrado como una tarea del proyecto en la vista Tareas; no hace falta crearla a mano.",
					"Una tarea no está terminada porque se tocaron archivos: está terminada cuando hay prueba que se pueda VER.",
					"- Si el cambio se ve en pantalla, capturá la app real (pantalla-agente montar y capturar, o grim) y guardá la imagen bajo el proyecto o /tmp.",
					"- Si hay tests o build, corrélos y mostrá cómo terminaron.",
					"- Cerrá nombrando las rutas de las imágenes o videos y qué prueba cada una; la tarjeta de Evidencia las levanta del log de la sesión.",
					"Sin captura ni prueba visual, la tarea queda sin evidencia visible.",
				].join("\n"),
			}),
		"tasks: instrucciones de evidencia",
	);

	ctx.logger?.info?.("tasks: tareas por proyecto y evidencia montadas");
}
