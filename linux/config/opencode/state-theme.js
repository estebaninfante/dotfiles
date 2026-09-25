const DEFAULTS = {
  thinking: "tokyonight",
  permission: "gruvbox",
  error: "matrix",
};

export default {
  id: "eztvn.state-theme",
  tui: async (api, options) => {
    const themes = { ...DEFAULTS, ...(options?.themes ?? {}) };
    const ignored = new Set(options?.ignoreSessions ?? []);
    let base;
    let current;
    let errorSession;
    let disposed = false;

    const routeSession = () => {
      const route = api.route?.current;
      const id = route?.name === "session" ? route.params?.sessionID : undefined;
      return typeof id === "string" && id ? id : undefined;
    };

    const root = (id) => {
      const seen = new Set();
      while (typeof id === "string" && !seen.has(id)) {
        seen.add(id);
        const session = api.state.session.get(id);
        if (!session || !session.parentID) return id;
        id = session.parentID;
      }
      return id;
    };

    const stateOf = (id) => {
      if (errorSession === id) return "error";
      if ((api.state.session.permission(id) ?? []).length > 0) return "permission";
      if ((api.state.session.question(id) ?? []).length > 0) return "permission";
      const type = api.state.session.status(id)?.type;
      return type && type !== "idle" ? "thinking" : "idle";
    };

    const themeFor = (state) => {
      if (state === "idle") return base;
      const name = themes[state];
      return name && api.theme.has(name) ? name : base;
    };

    const apply = () => {
      if (disposed || !api.theme.ready) return;
      if (base === undefined) base = api.theme.selected || api.tuiConfig?.theme || "system";
      const sid = routeSession();
      if (!sid || ignored.has(sid)) {
        if (current !== "idle" && api.theme.set(base)) current = "idle";
        return;
      }
      const id = root(sid);
      const state = stateOf(id);
      if (state === current) return;
      const name = themeFor(state);
      if (name && api.theme.selected !== name && api.theme.set(name)) current = state;
    };

    const schedule = () => void queueMicrotask(apply);

    const sid = (event) =>
      typeof event?.properties?.sessionID === "string"
        ? root(event.properties.sessionID)
        : undefined;

    const subscriptions = [];
    const listen = (type, handler) => {
      try {
        subscriptions.push(api.event.on(type, handler));
      } catch {}
    };

    listen("permission.asked", schedule);
    listen("permission.replied", schedule);
    listen("question.asked", schedule);
    listen("question.replied", schedule);
    listen("question.rejected", schedule);
    listen("session.created", schedule);
    listen("session.updated", schedule);
    listen("session.deleted", schedule);
    listen("session.idle", (event) => {
      if (errorSession && sid(event) === errorSession) errorSession = undefined;
      schedule();
    });
    listen("session.status", (event) => {
      if (errorSession && sid(event) === errorSession) errorSession = undefined;
      schedule();
    });
    listen("session.error", (event) => {
      const id = sid(event);
      if (id) errorSession = id;
      schedule();
    });

    const poll = setInterval(apply, 250);
    if (!api.theme.ready) {
      const wait = setInterval(() => {
        if (api.theme.ready) {
          clearInterval(wait);
          apply();
        }
      }, 250);
      wait.unref?.();
      api.lifecycle.onDispose(() => clearInterval(wait));
    }

    const dispose = () => {
      disposed = true;
      clearInterval(poll);
      for (const off of subscriptions) off?.();
      subscriptions.length = 0;
      if (base && api.theme.ready) api.theme.set(base);
    };
    api.lifecycle.onDispose(dispose);

    apply();
  },
};
