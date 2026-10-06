import { openMcp } from './client.mjs'

const [command, ...args] = process.argv.slice(2)
if (!command) {
  console.error('uso: node list.mjs <command> [args...]')
  process.exit(2)
}

const mcp = await openMcp({ command, args })
console.log(
  JSON.stringify(
    mcp.tools.map((t) => ({ name: t.name, description: t.description, schema: t.inputSchema })),
    null,
    2,
  ),
)
await mcp.close()
