import * as agentBrowser from './agent-browser.mjs'
import * as browserControl from './browser-control.mjs'
import * as braveMcp from './brave-mcp.mjs'
import * as playwrightMcp from './playwright-mcp.mjs'
import * as chromeDevtoolsMcp from './chrome-devtools-mcp.mjs'
import * as stagehand from './stagehand.mjs'

export const adapters = [
  agentBrowser,
  browserControl,
  braveMcp,
  playwrightMcp,
  chromeDevtoolsMcp,
  stagehand,
]

export async function listAvailable() {
  const out = []
  for (const a of adapters) {
    let ok = false
    try {
      ok = await a.available()
    } catch {
      ok = false
    }
    out.push({ adapter: a, available: ok })
  }
  return out
}
