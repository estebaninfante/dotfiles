// Prueba del fold: eventos sintéticos con valores conocidos y, si se le pasa
// una ruta (o sin ruta, la sesión más nueva), smoke test contra un log real.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { foldSession } from "../lib/fold.js";

const header = { id: "session-test", cwd: "/home/user/app", createdAt: 1, version: 4, isSeeded: false };
const events = [
	{ type: "turn/start", seq: 0, time: 0, data: { turn: 1 } },
	{ type: "step/start", seq: 1, time: 0, data: { turn: 1, step: 1 } },
	{ type: "assistant/message", seq: 2, time: 1000, data: { turn: 1, step: 1, usage: { inputTokens: 100, cacheReadTokens: 1000, outputTokens: 50, totalTokens: 1150 } } },
	{ type: "tool/call", seq: 3, time: 1100, data: { turn: 1, step: 1, callId: "c1", name: "bash" } },
	{ type: "tool/result", seq: 4, time: 2100, data: { turn: 1, step: 1, message: { source: { callId: "c1" }, isError: false } } },
	{ type: "step/start", seq: 5, time: 2100, data: { turn: 1, step: 2 } },
	{ type: "llm/retry", seq: 6, time: 302100, data: { turn: 1, step: 2, failure: { code: "TIMEOUT" } } },
	{ type: "assistant/attempt", seq: 7, time: 302100, data: { turn: 1, step: 2, stream: [{ type: "chunk", time: 302100, chunk: { type: "finish", reason: { kind: "error", failure: { code: "TIMEOUT", message: "timeout" } } } }] } },
	{ type: "assistant/message", seq: 8, time: 304100, data: { turn: 1, step: 2, usage: { inputTokens: 200, cacheReadTokens: 2000, outputTokens: 80, totalTokens: 2280 } } },
	{ type: "turn/end", seq: 9, time: 305100, data: { turn: 1, reason: { kind: "completed" } } },
];

const result = foldSession(header, events);
assert.equal(result.session.id, "session-test");
assert.equal(result.counts.turns, 1);
assert.equal(result.counts.steps, 2);
assert.equal(result.counts.requests, 2);
assert.equal(result.counts.toolCalls, 1);
assert.equal(result.counts.retries, 1);
assert.equal(result.counts.failures, 1);
assert.equal(result.counts.turnsEnded, 1);
assert.deepEqual(result.outcomes, { completed: 1 });
assert.equal(result.session.wallMs, 305100);
assert.equal(result.time.modelMs, 303000);
assert.equal(result.time.toolMs, 1000);
assert.equal(result.time.waitMs, 1100);
assert.equal(result.latency.samples, 2);
assert.equal(result.latency.cleanP50, 1000);
assert.equal(result.latency.slow, 1);
assert.equal(result.gaps.count, 1);
assert.equal(result.gaps.ms, 300000);
assert.deepEqual(result.failures, [{ code: "TIMEOUT", count: 1 }]);
assert.equal(result.tools.length, 1);
assert.deepEqual(result.tools[0], { name: "bash", calls: 1, ms: 1000, p50: 1000, max: 1000, errors: 0 });
assert.equal(result.tokens.input, 300);
assert.equal(result.tokens.cacheRead, 3000);
assert.equal(result.tokens.output, 130);
assert.deepEqual(result.context, { first: 1100, last: 2200, max: 2200 });
assert.ok(Math.abs(result.tokens.cacheHitPct - 90.909) < 0.01);
assert.ok(Math.abs(result.tokens.speed - 0.429) < 0.01);

function sessionFiles() {
	const root = join(homedir(), ".dsh", "sessions");
	const files = [];
	for (const cwd of readdirSync(root)) {
		const dir = join(root, cwd);
		if (!statSync(dir).isDirectory()) continue;
		for (const session of readdirSync(dir)) {
			const file = join(dir, session, "session.v4.jsonl.zstd");
			try {
				files.push({ file, age: statSync(file).mtimeMs });
			} catch {}
		}
	}
	return files.sort((left, right) => right.age - left.age).map((entry) => entry.file);
}

function readSession(file) {
	// El log durable es zstd multi-frame (una trama por append): node:zlib se
	// queda en la primera, así que acá se usa el binario zstd.
	const result = spawnSync("zstd", ["-dc", file], { maxBuffer: 512 << 20 });
	if (result.status !== 0) throw new Error(result.stderr.toString("utf8") || "zstd failed");
	const lines = result.stdout.toString("utf8").split("\n").filter(Boolean);
	return { header: JSON.parse(lines[0]), events: lines.slice(1).map((line) => JSON.parse(line)) };
}

let real = process.argv[2] ?? null;
if (real === null) {
	for (const file of sessionFiles()) {
		try {
			const candidate = readSession(file);
			if (candidate.events.some((event) => event.type === "step/start")) {
				real = file;
				break;
			}
		} catch {}
	}
}
if (real !== null) {
	const { header: realHeader, events: realEvents } = readSession(real);
	const realResult = foldSession(realHeader, realEvents);
	assert.ok(realResult.counts.steps > 0, "la sesión real no tiene steps");
	assert.ok(realResult.counts.requests > 0, "la sesión real no tiene requests");
	assert.ok(realResult.counts.steps >= realResult.counts.requests, "steps < requests");
	assert.ok(realResult.time.modelMs >= 0 && realResult.time.toolMs >= 0);
	console.log(
		"real:",
		realHeader.id,
		"turns", realResult.counts.turns,
		"steps", realResult.counts.steps,
		"requests", realResult.counts.requests,
		"tools", realResult.counts.toolCalls,
		"retries", realResult.counts.retries,
		"p50", realResult.latency.p50,
		"ctxMax", realResult.context.max,
	);
	if (process.env.METRICS_JSON === "1") console.log(JSON.stringify(realResult));
}

console.log("ok: fold");
