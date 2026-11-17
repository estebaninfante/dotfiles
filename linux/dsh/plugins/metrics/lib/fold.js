/**
 * dsh-local-metrics — fold del log durable a métricas de una conversación.
 *
 * Puro: recibe el header de la sesión y sus eventos ya validados por la
 * persistencia, y devuelve un objeto serializable. Sin fs, sin red, sin
 * dependencias: el mismo código se usa en la ruta del host y en las pruebas.
 */

/** Hueco entre eventos consecutivos que cuenta como espera muerta. */
const GAP_MS = 120_000;
/** Request más lenta que esto se cuenta como lenta (aunque termine). */
const SLOW_REQUEST_MS = 120_000;

function percentile(sorted, p) {
	if (sorted.length === 0) return null;
	const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1));
	return sorted[index];
}

function sortedMs(values) {
	return values.slice().sort((a, b) => a - b);
}

function sum(values) {
	let total = 0;
	for (const value of values) total += value;
	return total;
}

function num(value) {
	return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0;
}

function finishOf(attempt) {
	const stream = attempt.stream;
	if (!Array.isArray(stream)) return undefined;
	for (const entry of stream) {
		if (entry?.chunk?.type === "finish") return entry.chunk;
	}
	return undefined;
}

/**
 * @param header - header durable de la sesión (`id`, `cwd`, `createdAt`, …).
 * @param events - eventos durables en orden de seq.
 * @returns métricas planas para la vista.
 */
export function foldSession(header, events) {
	const counts = { turns: 0, steps: 0, requests: 0, failures: 0, toolCalls: 0, userMessages: 0, retries: 0 };
	const outcomes = Object.create(null);
	const failures = new Map();
	const tools = new Map();
	const calls = new Map();
	const stepStart = new Map();
	const retriedSteps = new Set();
	const turnStart = new Map();
	const turnDurations = [];
	const requestDurations = [];
	const cleanDurations = [];
	const contexts = [];
	const usage = { input: 0, cacheRead: 0, output: 0 };
	const gaps = [];
	let modelMs = 0;
	let toolMs = 0;
	let first = null;
	let last = null;
	let previous = null;
	let pendingTools = 0;
	let images = 0;
	let title = null;
	let model = null;

	for (const event of events) {
		const type = event.type;
		const data = event.data ?? {};
		const time = typeof event.time === "number" ? event.time : null;
		if (time !== null) {
			if (first === null) first = time;
			last = time;
			if (previous !== null && time >= previous && pendingTools === 0) {
				const gap = time - previous;
				if (gap > GAP_MS) gaps.push(gap);
			}
			previous = time;
		}

		switch (type) {
			case "turn/start":
				counts.turns += 1;
				turnStart.set(data.turn, time);
				break;
			case "turn/end": {
				const kind = data.reason?.kind ?? "unknown";
				outcomes[kind] = (outcomes[kind] ?? 0) + 1;
				const started = turnStart.get(data.turn);
				if (started !== undefined && started !== null && time !== null) turnDurations.push(time - started);
				break;
			}
			case "step/start":
				counts.steps += 1;
				stepStart.set(`${data.turn}:${data.step}`, time);
				break;
			case "llm/retry":
				counts.retries += 1;
				retriedSteps.add(`${data.turn}:${data.step}`);
				break;
			case "assistant/attempt": {
				const finish = finishOf(data);
				if (finish?.reason?.kind === "error") {
					counts.failures += 1;
					const code = finish.reason.failure?.code ?? "ERROR";
					failures.set(code, (failures.get(code) ?? 0) + 1);
				}
				break;
			}
			case "assistant/message": {
				counts.requests += 1;
				const key = `${data.turn}:${data.step}`;
				const started = stepStart.get(key);
				if (started !== undefined && started !== null && time !== null) {
					const duration = time - started;
					requestDurations.push(duration);
					modelMs += duration;
					if (!retriedSteps.has(key)) cleanDurations.push(duration);
				}
				const record = data.usage ?? {};
				const output = num(record.outputTokens);
				usage.input += num(record.inputTokens);
				usage.cacheRead += num(record.cacheReadTokens);
				usage.output += output;
				const total = num(record.totalTokens);
				if (total > 0) contexts.push(Math.max(0, total - output));
				break;
			}
			case "tool/call":
				counts.toolCalls += 1;
				calls.set(data.callId, { name: data.name, time });
				pendingTools += 1;
				break;
			case "tool/result": {
				const callId = data.message?.source?.callId ?? data.message?.toolCallId;
				const call = calls.get(callId);
				if (pendingTools > 0) pendingTools -= 1;
				const name = call?.name ?? "unknown";
				const aggregate = tools.get(name) ?? { calls: 0, ms: 0, durations: [], errors: 0 };
				aggregate.calls += 1;
				if (call && call.time !== null && time !== null) {
					const duration = time - call.time;
					aggregate.durations.push(duration);
					aggregate.ms += duration;
					toolMs += duration;
				}
				if (data.message?.isError === true) aggregate.errors += 1;
				tools.set(name, aggregate);
				break;
			}
			case "user/message":
				counts.userMessages += 1;
				break;
			case "request/header": {
				const config = data.header?.config;
				if (config !== undefined && config !== null) model = { provider: config.provider ?? null, model: config.model ?? null };
				break;
			}
			case "session/title":
				if (typeof data.title === "string") title = data.title;
				break;
			case "image/offload":
				images += Array.isArray(data.targets) ? data.targets.length : 1;
				break;
			default:
				break;
		}
	}

	const wallMs = first !== null && last !== null ? last - first : 0;
	const requestSorted = sortedMs(requestDurations);
	const cleanSorted = sortedMs(cleanDurations);
	const contextFirst = contexts.length > 0 ? contexts[0] : null;
	const contextLast = contexts.length > 0 ? contexts[contexts.length - 1] : null;
	const contextMax = contexts.length > 0 ? Math.max(...contexts) : null;
	const billed = usage.input + usage.cacheRead;

	return {
		session: {
			id: header?.id ?? null,
			cwd: header?.cwd ?? null,
			origin: header?.origin ?? null,
			createdAt: header?.createdAt ?? null,
			title,
			first,
			last,
			wallMs,
		},
		model,
		counts: { ...counts, turnsEnded: sum(Object.values(outcomes)) },
		outcomes: { ...outcomes },
		time: {
			modelMs,
			toolMs,
			waitMs: Math.max(0, wallMs - modelMs - toolMs),
			turnAvgMs: turnDurations.length > 0 ? sum(turnDurations) / turnDurations.length : null,
			turnMaxMs: turnDurations.length > 0 ? Math.max(...turnDurations) : null,
		},
		latency: {
			samples: requestSorted.length,
			p50: percentile(requestSorted, 0.5),
			p90: percentile(requestSorted, 0.9),
			p95: percentile(requestSorted, 0.95),
			max: requestSorted.length > 0 ? requestSorted[requestSorted.length - 1] : null,
			cleanP50: percentile(cleanSorted, 0.5),
			cleanP90: percentile(cleanSorted, 0.9),
			slow: requestDurations.filter((value) => value > SLOW_REQUEST_MS).length,
		},
		tokens: {
			input: usage.input,
			cacheRead: usage.cacheRead,
			output: usage.output,
			cacheHitPct: billed > 0 ? (usage.cacheRead / billed) * 100 : null,
			speed: modelMs > 0 ? usage.output / (modelMs / 1000) : null,
		},
		context: {
			first: contextFirst,
			last: contextLast,
			max: contextMax,
		},
		gaps: {
			count: gaps.length,
			ms: sum(gaps),
			longest: gaps.length > 0 ? Math.max(...gaps) : null,
		},
		tools: [...tools.entries()]
			.map(([name, aggregate]) => ({
				name,
				calls: aggregate.calls,
				ms: aggregate.ms,
				p50: percentile(sortedMs(aggregate.durations), 0.5),
				max: aggregate.durations.length > 0 ? Math.max(...aggregate.durations) : null,
				errors: aggregate.errors,
			}))
			.sort((left, right) => right.ms - left.ms || right.calls - left.calls),
		failures: [...failures.entries()]
			.map(([code, count]) => ({ code, count }))
			.sort((left, right) => right.count - left.count),
		images,
	};
}
