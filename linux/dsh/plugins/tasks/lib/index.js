/**
 * dsh-local-tasks — host half.
 *
 * Tareas por proyecto (carpeta) y evidencia real de cada conversación tomada del
 * log de la sesión (`ctx.sessionQuery`), no de lo que el agente dice.
 *
 * La tarea la nombra el agente con `task_plan`: un título elegido por él que
 * describe el trabajo. El mensaje del usuario nunca es título. Un turno de
 * continuación ("continue", "dale") no crea tarea: suma su evidencia a la
 * tarea abierta. Las rutas HTTP viven en routes.js.
 */
import { rootSession, textOfMessage } from "./events.js";
import { isContinuation, planTasks } from "./plan.js";
import { registerRoutes } from "./routes.js";
import { addTurn, adoptTurn, createTask, findOpenTask, findSessionTasks, findTurnTasks, updateTask } from "./store.js";

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
		continuation: new Map(),
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
							pending: {
								type: "array",
								items: {
									type: "object",
									additionalProperties: false,
									properties: { title: { type: "string" }, turn: { type: "number" }, outcome: { type: "string" }, state: { type: "string" } },
									required: ["title", "turn", "state"],
								},
							},
						},
						required: ["tasks", "pending"],
					},
					render: (_args, value) => {
						const names = value.tasks.map((task) => task.title).join(" · ") || "(ninguna)";
						const pending = value.pending.map((task) => `${task.title} (turno ${task.turn}${task.outcome ? `, ${task.outcome}` : ""})`).join(" · ");
						return [{ type: "text", text: `Tareas del pedido: ${names}${pending ? `\nPendientes de turnos anteriores: ${pending}` : ""}` }];
					},
				},
				async execute(args, exec) {
					const session = exec.agent?.session;
					if (!session?.header?.cwd) return { tasks: [], pending: [] };
					const sessionId = session.id;
					const turn = live.currentTurn.get(sessionId) ?? 1;
					const plan = planTasks(args);
					if (!plan.length) return { tasks: [], pending: [] };
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
					const pending = (await findSessionTasks(sessionId))
						.filter((task) => task.turn !== turn && (task.state === "abierta" || task.outcome === "falló" || task.outcome === "parcial" || task.outcome === "abierta"))
						.map((task) => ({ title: task.title, turn: task.turn ?? 0, outcome: task.outcome ?? "", state: task.state }));
					return { tasks: registered, pending };
				},
			}),
		"tasks: nombrar el pedido",
	);

	ctx.effect(
		() =>
			ctx.tools.register({
				name: "task_review",
				description:
					"Revisá las tareas de esta conversación al final del turno: marcá en cuáles terminaste (ok), en cuáles fallaste (falló), cuáles quedaron parciales y cuáles siguen abiertas, con una línea de qué pasó. Después contale al usuario las que quedaron abiertas o fallaron.",
				parameters: {
					type: "object",
					additionalProperties: false,
					properties: {
						items: {
							type: "array",
							description: "Una entrada por tarea de esta conversación. Las que no marques quedan sin revisar.",
							items: {
								type: "object",
								additionalProperties: false,
								properties: {
									id: { type: "string", description: "id que devolvió task_plan." },
									outcome: { type: "string", enum: ["ok", "parcial", "falló", "abierta", "cancelada"] },
									note: { type: "string", description: "Qué pasó con esta tarea, en una línea." },
								},
								required: ["id", "outcome"],
							},
						},
					},
					required: ["items"],
				},
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
									properties: {
										id: { type: "string" },
										title: { type: "string" },
										turn: { type: "number" },
										state: { type: "string" },
										outcome: { type: "string" },
										note: { type: "string" },
									},
									required: ["id", "title", "turn", "state", "outcome", "note"],
								},
							},
							open: { type: "number" },
							failed: { type: "number" },
						},
						required: ["tasks", "open", "failed"],
					},
					render: (_args, value) => {
						const ok = value.tasks.filter((task) => task.outcome === "ok").length;
						const pending = value.tasks.filter((task) => task.state !== "resuelta" && task.outcome !== "ok").map((task) => `${task.title} (${task.outcome || "sin revisar"})`);
						return [
							{
								type: "text",
								text: `Revisión del turno: ${ok} ok · ${value.failed} fallaron · ${value.open} abiertas${pending.length ? `\nPendientes: ${pending.join(" · ")}` : ""}`,
							},
						];
					},
				},
				async execute(args, exec) {
					const session = exec.agent?.session;
					if (!session) return { tasks: [], open: 0, failed: 0 };
					const items = Array.isArray(args?.items) ? args.items : [];
					for (const item of items) {
						if (typeof item?.id !== "string") continue;
						await updateTask(item.id, { outcome: item.outcome, note: item.note }).catch(() => null);
					}
					const shaped = (await findSessionTasks(session.id)).map((task) => ({
						id: task.id,
						title: task.title,
						turn: task.turn ?? 0,
						state: task.state,
						outcome: task.outcome ?? "",
						note: task.note ?? "",
					}));
					const open = shaped.filter((task) => task.state !== "resuelta" && task.state !== "cancelada" && (task.outcome === "" || task.outcome === "abierta" || task.outcome === "parcial")).length;
					const failed = shaped.filter((task) => task.outcome === "falló").length;
					return { tasks: shaped, open, failed };
				},
			}),
		"tasks: revisar al cerrar",
	);

	// La tarea existe porque el agente la nombró. Un mensaje de continuación no
	// crea tarea nueva: su evidencia suma a la tarea abierta de la conversación.
	// El título nunca es el mensaje del usuario.
	async function registerRequest(session) {
		const sessionId = session.id;
		const turn = live.currentTurn.get(sessionId);
		const request = live.requestText.get(sessionId) ?? "";
		if (!turn || !request) return;
		if ((await findTurnTasks(sessionId, turn)).length) return;
		if (isContinuation(request)) {
			live.continuation.set(sessionId, turn);
			const open = await findOpenTask(sessionId);
			if (open) await addTurn(open.id, turn);
			return;
		}
		live.continuation.delete(sessionId);
		// Tarea creada desde la UI que todavía no sabe de qué turno salió.
		if (await adoptTurn(sessionId, turn)) return;
		// Pedido nuevo: la tarea la nombra el agente con task_plan. Mientras tanto
		// no se inventa título con el mensaje del usuario.
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
			live.continuation.delete(session.id);
			if (live.requestText.has(session.id)) scheduleRegister(session);
			return;
		}
		if (event.type === "turn/end") {
			const turn = Number(event.data?.turn ?? 0);
			const reason = String(event.data?.reason?.kind ?? "?");
			live.running.delete(session.id);
			if (Number.isSafeInteger(turn) && turn > 0) {
				live.turnEnds.set(session.id, { turn, reason });
				// El usuario detuvo el turno: la tarea queda cancelada, no "abierta".
				const cancelled = reason === "interrupted" || reason === "aborted";
				findTurnTasks(session.id, turn)
					.then((tasks) =>
						Promise.all(
							tasks.map((task) =>
								updateTask(task.id, {
									closeReason: reason,
									closedAt: Date.now(),
									...(cancelled ? { state: "cancelada" } : {}),
									// Cierre automático si el agente no llamó a task_review:
									// completado = ok; error = falló; cancelada = cancelada.
									...(task.outcome
										? {}
										: {
												outcome: cancelled ? "cancelada" : reason === "completed" ? "ok" : reason === "error" ? "falló" : "abierta",
												note: cancelled ? "el usuario detuvo el turno" : "cierre automático (sin revisión del agente)",
											}),
								}),
							),
						),
					)
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
				// Un "continue" no es una tarea nueva: sigue la que ya está abierta.
				if (live.continuation.get(session.id) === turn) return undefined;
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
					"Al terminar el trabajo, antes de tu respuesta final, llamá a `task_review` con el resultado de cada tarea de esta conversación: `ok` si la terminaste con prueba, `parcial` si quedó a medias, `falló` si no salió y `abierta` si sigue pendiente, con una línea de qué pasó. Después decile al usuario qué quedó abierto o falló y qué sigue.",
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
