/**
 * dsh-local-tasks — host half.
 *
 * Tareas por proyecto (carpeta) y evidencia real de cada conversación tomada del
 * log de la sesión (`ctx.sessionQuery`), no de lo que el agente dice.
 *
 * Cada pedido del usuario se registra como tarea; el agente la nombra con
 * `task_plan` (uno o varios títulos si el pedido pide varias cosas) y un guard
 * le impide trabajar hasta que la nombró. Las rutas HTTP viven en routes.js.
 */
import { firstLine, rootSession, textOfMessage } from "./events.js";
import { planTasks } from "./plan.js";
import { registerRoutes } from "./routes.js";
import { adoptTurn, createTask, findSessionTask, findTurnTask, findTurnTasks, updateTask } from "./store.js";

export const inject = ["webServer", "sessionQuery", "systemPrompt", "tools"];

const TASK_PLAN_DESCRIPTION =
	"Nombrá las tareas de este pedido antes de trabajar. Una entrada por cada cosa distinta que pidió el usuario, con un título corto y concreto (3 a 8 palabras, en el idioma del usuario).";

const TASK_PLAN_PARAMETERS = {
	type: "object",
	additionalProperties: false,
	properties: {
		tasks: {
			type: "array",
			description: "Tareas del pedido, en el orden en que conviene hacerlas.",
			items: {
				type: "object",
				additionalProperties: false,
				properties: {
					title: { type: "string", description: "Nombre corto y concreto de la tarea." },
					detail: { type: "string", description: "Qué incluye esta tarea, en una línea (opcional)." },
				},
				required: ["title"],
			},
		},
	},
	required: ["tasks"],
};

export function apply(ctx) {
	// Estado en vivo de los pedidos: turno actual, cierre, nombrado y registro.
	const live = {
		currentTurn: new Map(),
		turnEnds: new Map(),
		running: new Set(),
		planned: new Map(),
		denials: new Map(),
		inflight: new Map(),
		requestText: new Map(),
	};
	registerRoutes(ctx, live);

	ctx.effect(
		() =>
			ctx.tools.register({
				name: "task_plan",
				description: `${TASK_PLAN_DESCRIPTION} Si el pedido tiene una sola tarea, una sola entrada.`,
				parameters: TASK_PLAN_PARAMETERS,
				output: {
					schema: {
						type: "object",
						additionalProperties: false,
						properties: {
							tasks: {
								type: "array",
								items: {
									type: "object",
									additionalProperties: false,
									properties: { id: { type: "string" }, title: { type: "string" } },
									required: ["id", "title"],
								},
							},
						},
						required: ["tasks"],
					},
					render: (_args, value) => [{ type: "text", text: `Tareas del pedido: ${value.tasks.map((task) => task.title).join(" · ") || "(ninguna)"}` }],
				},
				async execute(args, exec) {
					const session = exec.agent?.session;
					if (!session?.header?.cwd) return { tasks: [] };
					const sessionId = session.id;
					const turn = live.currentTurn.get(sessionId) ?? 1;
					const plan = planTasks(args);
					if (!plan.length) return { tasks: [] };
					const existing = await findTurnTasks(sessionId, turn);
					const registered = [];
					for (let index = 0; index < plan.length; index += 1) {
						const item = plan[index];
						const task =
							index === 0 && existing[0]
								? await updateTask(existing[0].id, { title: item.title, goal: item.detail })
								: await createTask({ workspace: session.header.cwd, title: item.title, goal: item.detail, sessionId, turn, origin: "auto" });
						registered.push({ id: task.id, title: task.title });
					}
					live.planned.set(sessionId, turn);
					return { tasks: registered };
				},
			}),
		"tasks: nombrar el pedido",
	);

	// Un turno = un pedido. Solo cuentan los mensajes con source.kind "user":
	// los recordatorios y el runtime context del harness también llegan como
	// user/message y no son pedidos. El título provisorio es la primera línea.
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
		await createTask({
			workspace: session.header.cwd,
			title: firstLine(request) || `Pedido del turno ${turn}`,
			sessionId,
			turn,
			origin: "auto",
		});
	}
	function scheduleRegister(session) {
		const sessionId = session.id;
		if (live.inflight.has(sessionId)) return;
		const job = registerRequest(session).catch(() => undefined);
		live.inflight.set(sessionId, job);
		job.finally(() => {
			live.inflight.delete(sessionId);
			live.requestText.delete(sessionId);
		});
	}
	ctx.on("session/event", (session, event) => {
		if (!rootSession(session)) return;
		if (event.type === "turn/start") {
			const turn = Number(event.data?.turn ?? 0);
			if (!Number.isSafeInteger(turn) || turn <= 0) return;
			live.currentTurn.set(session.id, turn);
			live.running.add(session.id);
			live.denials.delete(session.id);
			if (live.requestText.has(session.id)) scheduleRegister(session);
			return;
		}
		if (event.type === "turn/end") {
			const turn = Number(event.data?.turn ?? 0);
			const reason = String(event.data?.reason?.kind ?? "?");
			live.running.delete(session.id);
			if (Number.isSafeInteger(turn) && turn > 0) {
				live.turnEnds.set(session.id, { turn, reason });
				findTurnTasks(session.id, turn)
					.then((tasks) => Promise.all(tasks.map((task) => updateTask(task.id, { closeReason: reason, closedAt: Date.now() }))))
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
				const session = execution?.agent?.session;
				if (!session || !rootSession(session)) return undefined;
				const turn = live.currentTurn.get(session.id);
				if (!turn) return undefined;
				if (live.planned.get(session.id) === turn) return undefined;
				if (execution.name === "task_plan" || execution.name === "ask_user_question") return undefined;
				const denials = live.denials.get(session.id) ?? 0;
				if (denials >= 2) return undefined;
				live.denials.set(session.id, denials + 1);
				return "Primero nombrá este pedido: llamá a task_plan con un título corto por cada cosa distinta que pidió el usuario.";
			}),
		"tasks: cada pedido se nombra antes de trabajar",
	);

	ctx.effect(
		() =>
			ctx.systemPrompt.section({
				name: "local-tasks/evidence",
				order: 45,
				text: [
					"## Tareas y evidencia",
					"Cada pedido del usuario se registra como una tarea del proyecto en la vista Tareas.",
					"Al empezar cada turno llamá a `task_plan` con las tareas del pedido: un título corto y concreto (3 a 8 palabras) por cada cosa distinta que pidió. Si pidió una sola cosa, una sola entrada. Después trabajás; las herramientas están bloqueadas hasta que el pedido tenga nombre.",
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
