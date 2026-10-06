import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport, getDefaultEnvironment } from '@modelcontextprotocol/sdk/client/stdio.js'

export async function openMcp({ command, args = [], env = {} }) {
  const transport = new StdioClientTransport({
    command,
    args,
    env: { ...getDefaultEnvironment(), ...env },
    stderr: 'pipe',
  })
  const client = new Client({ name: 'browser-bench', version: '0.1.0' })
  await client.connect(transport)
  const listed = await client.listTools()
  const tools = listed.tools ?? []

  const call = async (name, mcpArgs = {}) => {
    const res = await client.callTool({ name, arguments: mcpArgs })
    return { raw: res, text: mcpText(res) }
  }

  const close = async () => {
    try {
      await client.close()
    } catch {}
  }

  return { client, tools, toolNames: tools.map((t) => t.name), call, close }
}

export function mcpText(res) {
  const parts = res?.content ?? []
  return parts
    .filter((p) => p?.type === 'text')
    .map((p) => p.text ?? '')
    .join('\n')
}

export async function withMcp(opts, fn) {
  const mcp = await openMcp(opts)
  try {
    return await fn(mcp)
  } finally {
    await mcp.close()
  }
}
