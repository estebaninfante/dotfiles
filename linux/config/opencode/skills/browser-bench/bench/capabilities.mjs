export const capabilities = {
  'agent-browser': {
    realProfile: true,
    goal: 8,
    ext: 8,
    maint: 9,
    note: 'refs a11y, snapshot --delta, batch, profile copy read-only, MCP+CLI, allowed-domains',
  },
  'browser-control': {
    realProfile: true,
    goal: 10,
    ext: 8,
    maint: 7,
    note: 'execute() Playwright JS arbitrario, relay+sessions, network/secrets/recording, MCP+CLI',
  },
  'brave-mcp': {
    realProfile: true,
    goal: 7,
    ext: 9,
    maint: 6,
    note: 'devtools parity full (perf/red/heap/lighthouse), attach Brave real, 30 tools, CLI; fork 28 stars',
  },
  'playwright-mcp': {
    realProfile: false,
    goal: 7,
    ext: 7,
    maint: 9,
    note: 'a11y snapshot, trace; real profile solo via --extension/--cdp-endpoint',
  },
  'chrome-devtools-mcp': {
    realProfile: false,
    goal: 7,
    ext: 9,
    maint: 9,
    note: 'Google official, CDP, perf/red; attach via --browserUrl',
  },
  stagehand: {
    realProfile: false,
    goal: 6,
    ext: 8,
    maint: 8,
    llmRequired: true,
    note: 'act/extract/observe self-healing requieren LLM key (no configurada) => goal capado a 6; SDK TS/Py/Go, local o Browserbase cloud. Medido solo page local.',
  },
}

export const weights = {
  tokens: 0.25,
  speed: 0.2,
  roundtrips: 0.1,
  realProfile: 0.15,
  goal: 0.15,
  ext: 0.05,
  maint: 0.05,
}
