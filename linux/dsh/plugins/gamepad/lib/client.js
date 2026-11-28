/**
 * dsh-local-gamepad — client half.
 *
 * Un mando de Nintendo (Switch Pro Controller o Joy-Con emparejado por
 * Bluetooth) manejando la GUI de DSH con la API Gamepad del navegador.
 *
 * La regla del dueño: las flechas del mando son EXACTAMENTE las flechas del
 * teclado. No navegamos la app por dentro: en cada pulsación emitimos un
 * KeyboardEvent real (key/code "ArrowUp", bubbles, cancelable) sobre el
 * elemento enfocado, así los mismos manejadores de teclado de DSH responden
 * igual que con un teclado físico, también dentro de un input o textarea.
 *
 * El mapeo se puede ajustar sin tocar el repo desde la consola del navegador:
 *
 *   window.__DSH_GAMEPAD_CONFIG__ = {
 *     deadzone: 0.5,          // 0..1, palanca para que cuente como flecha
 *     repeatMs: 200,          // auto-repeat al mantener
 *     sticks: false,          // apagar palancas
 *     dpad: { 12: null },     // apagar botones puntuales del D-pad
 *     buttons: { 3: null },   // apagar el mapeo de Y
 *   };
 *
 * Mapeo estándar (Chromium/Firefox/Edge):
 *   D-pad 12-15 → flechas        A → Enter        B → Escape
 *   X → Backspace                Y → Tab          R1 (5) → Tab
 *   L1 (4) → Shift+Tab           Start (9) → "/" (menú de comandos)
 *
 * Start se omite mientras se escribe: ahí un "/" se tipearía de verdad y
 * ensuciaría el texto. El resto se emite siempre, como el teclado físico.
 */
window.__ModuleLoader__.load({
  id: "dsh-local-gamepad",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    const ARROW = {
      up: { key: "ArrowUp", code: "ArrowUp" },
      down: { key: "ArrowDown", code: "ArrowDown" },
      left: { key: "ArrowLeft", code: "ArrowLeft" },
      right: { key: "ArrowRight", code: "ArrowRight" },
    };

    const DPAD_DEFAULTS = {
      12: ARROW.up,
      13: ARROW.down,
      14: ARROW.left,
      15: ARROW.right,
    };

    const BUTTON_DEFAULTS = {
      0: { key: "Enter", code: "Enter" },
      1: { key: "Escape", code: "Escape" },
      2: { key: "Backspace", code: "Backspace" },
      3: { key: "Tab", code: "Tab" },
      4: { key: "Tab", code: "Tab", shiftKey: true },
      5: { key: "Tab", code: "Tab" },
      9: { key: "/", code: "Slash", onlyWhenIdle: true },
    };

    /** keyCode/which para manejadores legacy; los navegadores modernos usan key. */
    const KEY_CODES = {
      ArrowUp: 38,
      ArrowDown: 40,
      ArrowLeft: 37,
      ArrowRight: 39,
      Enter: 13,
      Escape: 27,
      Backspace: 8,
      Tab: 9,
      Slash: 191,
    };

    const DEFAULTS = { deadzone: 0.35, repeatMs: 140, sticks: true };

    function idOf(spec) {
      return spec.code + (spec.shiftKey === true ? "|shift" : "");
    }

    function mergeMap(base, extra) {
      const out = { ...base };
      if (extra && typeof extra === "object") {
        for (const [index, spec] of Object.entries(extra)) {
          out[index] = spec === null ? null : spec;
        }
      }
      return out;
    }

    function readConfig() {
      const override = window.__DSH_GAMEPAD_CONFIG__;
      const cfg = { ...DEFAULTS };
      if (override && typeof override === "object") {
        if (Number.isFinite(override.deadzone)) {
          cfg.deadzone = Math.min(1, Math.max(0, override.deadzone));
        }
        if (Number.isFinite(override.repeatMs)) {
          cfg.repeatMs = Math.max(16, override.repeatMs);
        }
        if (typeof override.sticks === "boolean") cfg.sticks = override.sticks;
      }
      cfg.dpad = mergeMap(DPAD_DEFAULTS, override && override.dpad);
      cfg.buttons = mergeMap(BUTTON_DEFAULTS, override && override.buttons);
      return cfg;
    }

    function isTyping(element) {
      if (!element || typeof element.tagName !== "string") return false;
      const tag = element.tagName.toUpperCase();
      if (tag === "INPUT" || tag === "TEXTAREA") return true;
      return element.isContentEditable === true;
    }

    function focusTarget() {
      const doc = window.document;
      const active = doc && doc.activeElement;
      if (active && typeof active.dispatchEvent === "function") return active;
      return doc;
    }

    function buildEvent(type, spec, repeat) {
      const init = {
        key: spec.key,
        code: spec.code,
        location: 0,
        bubbles: true,
        cancelable: true,
        composed: true,
        repeat: repeat === true,
        shiftKey: spec.shiftKey === true,
        ctrlKey: false,
        altKey: false,
        metaKey: false,
        isComposing: false,
      };
      let event;
      try {
        event = new window.KeyboardEvent(type, init);
      } catch (error) {
        return undefined;
      }
      const legacy = KEY_CODES[spec.code] || 0;
      if (legacy > 0) {
        try {
          if (event.keyCode !== legacy) {
            Object.defineProperty(event, "keyCode", { value: legacy, configurable: true });
          }
          if (event.which !== legacy) {
            Object.defineProperty(event, "which", { value: legacy, configurable: true });
          }
        } catch (error) {
          // keyCode es de solo lectura en algunos motores: key/code alcanzan.
        }
      }
      return event;
    }

    function emitKey(type, spec, repeat) {
      const target = focusTarget();
      if (!target || typeof target.dispatchEvent !== "function") return false;
      const event = buildEvent(type, spec, repeat);
      if (!event) return false;
      try {
        return target.dispatchEvent(event) !== false;
      } catch (error) {
        return false;
      }
    }

    /** Lo que el mando pide en este frame, ya en términos de teclas. */
    function desiredKeys(cfg, now) {
      const wanted = new Map();
      const nav = window.navigator;
      if (!nav || typeof nav.getGamepads !== "function") return wanted;
      let pads;
      try {
        pads = nav.getGamepads();
      } catch (error) {
        return wanted;
      }
      if (!pads || typeof pads.length !== "number") return wanted;

      let pad = null;
      for (let i = 0; i < pads.length; i += 1) {
        if (pads[i] && pads[i].connected !== false) {
          pad = pads[i];
          break;
        }
      }
      if (!pad) return wanted;

      const buttons = pad.buttons || [];
      const pressed = (index) => {
        const button = buttons[index];
        return button !== undefined && button !== null && button.pressed === true;
      };

      for (const [index, spec] of Object.entries(cfg.dpad)) {
        if (spec && pressed(Number(index))) wanted.set(idOf(spec), spec);
      }

      const typing = isTyping(window.document && window.document.activeElement);
      for (const [index, spec] of Object.entries(cfg.buttons)) {
        if (!spec || !pressed(Number(index))) continue;
        if (spec.onlyWhenIdle === true && typing) continue;
        wanted.set(idOf(spec), spec);
      }

      if (cfg.sticks) {
        const axes = pad.axes || [];
        const x = Number(axes[0]) || 0;
        const y = Number(axes[1]) || 0;
        const ax = Math.abs(x);
        const ay = Math.abs(y);
        if (ax >= cfg.deadzone || ay >= cfg.deadzone) {
          const spec =
            ay >= ax
              ? y < 0
                ? ARROW.up
                : ARROW.down
              : x < 0
                ? ARROW.left
                : ARROW.right;
          wanted.set(idOf(spec), spec);
        }
      }

      return wanted;
    }

    function apply(ctx) {
      const win = window;
      if (!win || typeof win.requestAnimationFrame !== "function") return;

      const cfg = readConfig();
      const held = new Map();
      let rafId = 0;
      let stopped = false;

      const releaseAll = () => {
        for (const record of held.values()) emitKey("keyup", record.spec, false);
        held.clear();
      };

      const frame = (now) => {
        if (stopped) return;
        rafId = win.requestAnimationFrame(frame);

        const wanted = desiredKeys(cfg, now);
        for (const [id, record] of held) {
          if (wanted.has(id)) continue;
          emitKey("keyup", record.spec, false);
          held.delete(id);
        }
        for (const [id, spec] of wanted) {
          const record = held.get(id);
          if (!record) {
            held.set(id, { spec, lastAt: now });
            emitKey("keydown", spec, false);
          } else if (now - record.lastAt >= cfg.repeatMs) {
            record.lastAt = now;
            emitKey("keydown", spec, true);
          }
        }
      };

      const onPadChange = () => releaseAll();

      ctx.effect(() => {
        win.addEventListener("gamepadconnected", onPadChange, true);
        win.addEventListener("gamepaddisconnected", onPadChange, true);
        rafId = win.requestAnimationFrame(frame);
        return () => {
          stopped = true;
          if (rafId) win.cancelAnimationFrame(rafId);
          win.removeEventListener("gamepadconnected", onPadChange, true);
          win.removeEventListener("gamepaddisconnected", onPadChange, true);
          releaseAll();
        };
      }, "dsh-local-gamepad: mando como teclado");
    }

    exports.apply = apply;
    exports.inject = [];
    return module.exports;
  },
});
