/**
 * Prueba del plugin sin mando físico: reemplaza navigator.getGamepads() por un
 * mando falso, monta la mitad cliente y verifica los KeyboardEvent emitidos.
 *
 * Correr desde la raíz del plugin:
 *   node --test tests/gamepad.test.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";

class FakeKeyboardEvent {
  constructor(type, init = {}) {
    this.type = type;
    Object.assign(this, init);
    this.defaultPrevented = false;
    this.isTrusted = false;
    this.target = null;
  }

  preventDefault() {
    this.defaultPrevented = true;
  }

  stopPropagation() {}
}

let registration;
const bootstrapWindow = {
  __ModuleLoader__: {
    load(value) {
      registration = value;
    },
  },
};

globalThis.window = bootstrapWindow;
globalThis.document = { activeElement: null };
await import(new URL("../lib/client.js", import.meta.url).href);

function createHarness({ tagName = "BODY" } = {}) {
  const buttons = Array.from({ length: 17 }, () => ({ pressed: false, value: 0 }));
  const pad = { connected: true, buttons, axes: [0, 0, 0, 0] };
  const events = [];
  const active = {
    tagName,
    isContentEditable: false,
    dispatchEvent(event) {
      event.target = active;
      events.push(event);
      return !event.defaultPrevented;
    },
  };

  const listeners = new Map();
  const frames = new Map();
  let nextFrameId = 1;

  const composer = {
    tagName: "DIV",
    isContentEditable: true,
    focusCount: 0,
    matches(selector) {
      return selector === "[data-composer-input]";
    },
    focus() {
      composer.focusCount += 1;
    },
  };

  const document = {
    activeElement: active,
    body: active,
    querySelector(selector) {
      return selector === "[data-composer-input]" ? composer : null;
    },
  };

  const window = {
    document,
    navigator: { getGamepads: () => [pad] },
    KeyboardEvent: FakeKeyboardEvent,
    addEventListener(type, handler) {
      listeners.set(type, handler);
    },
    removeEventListener(type, handler) {
      if (listeners.get(type) === handler) listeners.delete(type);
    },
    requestAnimationFrame(callback) {
      const id = nextFrameId;
      nextFrameId += 1;
      frames.set(id, callback);
      return id;
    },
    cancelAnimationFrame(id) {
      frames.delete(id);
    },
  };

  return { window, pad, buttons, events, active, composer, listeners, frames };
}

function mount(harness, config) {
  if (config !== undefined) harness.window.__DSH_GAMEPAD_CONFIG__ = config;
  globalThis.window = harness.window;
  globalThis.document = harness.window.document;
  const client = registration.factory(() => {
    throw new Error("el plugin gamepad no debe requerir módulos del navegador");
  });
  const ctx = {
    effect(callback) {
      harness.cleanup = callback();
    },
  };
  client.apply(ctx);
  return client;
}

function tick(harness, now) {
  const pending = [...harness.frames.values()];
  harness.frames.clear();
  for (const callback of pending) callback(now);
}

function press(harness, index, pressed = true) {
  harness.buttons[index].pressed = pressed;
}

test("un D-pad arriba emite keydown/keyup ArrowUp reales", () => {
  const harness = createHarness();
  mount(harness);

  press(harness, 12);
  tick(harness, 1000);

  assert.equal(harness.events.length, 1);
  const down = harness.events[0];
  assert.equal(down.type, "keydown");
  assert.equal(down.key, "ArrowUp");
  assert.equal(down.code, "ArrowUp");
  assert.equal(down.keyCode, 38);
  assert.equal(down.bubbles, true);
  assert.equal(down.cancelable, true);
  assert.equal(down.repeat, false);
  assert.equal(down.target, harness.active);

  press(harness, 12, false);
  tick(harness, 1100);

  const up = harness.events.at(-1);
  assert.equal(up.type, "keyup");
  assert.equal(up.key, "ArrowUp");
  assert.equal(up.code, "ArrowUp");
  harness.cleanup();
});

test("las flechas del mando llegan también a un textarea enfocado", () => {
  const harness = createHarness({ tagName: "TEXTAREA" });
  mount(harness);

  press(harness, 13);
  tick(harness, 0);

  assert.equal(harness.events.length, 1);
  assert.equal(harness.events[0].key, "ArrowDown");
  assert.equal(harness.events[0].target, harness.active);
  harness.cleanup();
});

test("mantener el D-pad repite con throttle de 140 ms", () => {
  const harness = createHarness();
  mount(harness);

  press(harness, 12);
  tick(harness, 0);
  tick(harness, 100);
  tick(harness, 140);
  tick(harness, 200);
  tick(harness, 280);

  const downs = harness.events.filter((event) => event.type === "keydown");
  assert.equal(downs.length, 3);
  assert.equal(downs[0].repeat, false);
  assert.equal(downs[1].repeat, true);
  assert.equal(downs[2].repeat, true);
  harness.cleanup();
});

test("A/B/X/Y/L1/R1 emiten sus teclas", () => {
  const harness = createHarness();
  mount(harness);

  for (const index of [0, 1, 2, 3, 4, 5]) press(harness, index);
  tick(harness, 0);

  const keys = harness.events.map((event) => `${event.type}:${event.key}${event.shiftKey ? "+shift" : ""}`);
  assert.deepEqual(keys, [
    "keydown:Enter",
    "keydown:Escape",
    "keydown:Backspace",
    "keydown:Tab",
    "keydown:Tab+shift",
  ]);
  harness.cleanup();
});

test("Start enfoca el compositor sin escribir nada", () => {
  const harness = createHarness();
  mount(harness);

  press(harness, 9);
  tick(harness, 0);
  tick(harness, 140);
  tick(harness, 280);

  assert.equal(harness.events.length, 0);
  assert.equal(harness.composer.focusCount, 1, "enfoca una sola vez mientras se mantiene");
  harness.cleanup();
});

test("Start no roba el foco si se está tipeando en un input", () => {
  const harness = createHarness({ tagName: "INPUT" });
  mount(harness);

  press(harness, 9);
  tick(harness, 0);

  assert.equal(harness.events.length, 0);
  assert.equal(harness.composer.focusCount, 0);
  harness.cleanup();
});

test("la palanca respeta la deadzone y solo responde pasado 0.35", () => {
  const harness = createHarness();
  mount(harness);

  harness.pad.axes = [0, -0.2, 0, 0];
  tick(harness, 0);
  assert.equal(harness.events.length, 0);

  harness.pad.axes = [0, -0.9, 0, 0];
  tick(harness, 100);
  assert.equal(harness.events.at(-1).key, "ArrowUp");

  harness.pad.axes = [0.9, 0, 0, 0];
  harness.events.length = 0;
  tick(harness, 300);
  assert.equal(harness.events.at(-1).key, "ArrowRight");
  harness.cleanup();
});

test("la configuración del navegador ajusta deadzone y apaga botones", () => {
  const harness = createHarness();
  mount(harness, { deadzone: 0.6, dpad: { 12: null } });

  harness.pad.axes = [0, -0.5, 0, 0];
  tick(harness, 0);
  assert.equal(harness.events.length, 0);

  press(harness, 12);
  tick(harness, 100);
  assert.equal(harness.events.length, 0, "dpad 12 quedó apagado por configuración");

  harness.pad.axes = [0, -0.8, 0, 0];
  tick(harness, 300);
  assert.equal(harness.events.at(-1).key, "ArrowUp");
  harness.cleanup();
});

test("desconectar el mando suelta las teclas apretadas", () => {
  const harness = createHarness();
  mount(harness);

  assert.deepEqual([...harness.listeners.keys()].sort(), [
    "gamepadconnected",
    "gamepaddisconnected",
  ]);

  press(harness, 12);
  tick(harness, 0);
  assert.equal(harness.events.length, 1);

  harness.listeners.get("gamepaddisconnected")();
  assert.equal(harness.events.at(-1).type, "keyup");
  assert.equal(harness.events.at(-1).key, "ArrowUp");
  harness.cleanup();
});

test("al desmontar cancela el frame, quita listeners y suelta teclas", () => {
  const harness = createHarness();
  mount(harness);

  press(harness, 12);
  tick(harness, 0);
  assert.equal(harness.frames.size, 1);

  harness.cleanup();

  assert.equal(harness.events.at(-1).type, "keyup");
  assert.equal(harness.frames.size, 0);
  assert.equal(harness.listeners.size, 0);
});
