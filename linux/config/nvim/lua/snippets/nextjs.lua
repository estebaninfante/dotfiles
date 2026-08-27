-- Snippets propios Next.js/React (friendly-snippets no cubre todo).
-- Complementa: HTML/CSS/input/form/img vienen de friendly-snippets.
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

local M = {}

M.next_component = {
  -- Server Component (default en App Router)
  s("nsc", fmt([[
export default function {}() {{
  return (
    <{}>{}</{}>
  )
}}]], { i(1, "Componente"), i(2, "div"), i(3), l_rep(2) })),

  -- Client Component con useState
  s("ncc", fmt([[
'use client'

import {{ useState }} from 'react'

export default function {}() {{
  const [{} , set{}] = useState({})
  return (
    <div>{}</div>
  )
}}]], { i(1, "Componente"), i(2, "valor"), l_rep(2, true), i(4, ""), i(5) })),

  -- Metadata export (layout.tsx / page.tsx)
  s("nmeta", fmt([[
import type {{ Metadata }} from 'next'

export const metadata: Metadata = {{
  title: '{}',
  description: '{}',
}}]], { i(1, "Título"), i(2, "Descripción") })),
}

M.next_file_helpers = {
  -- <Link>
  s("nlink", fmt([[<Link href="{}" className="{}">{}</Link>]], { i(1, "/"), i(2), i(3) })),

  -- <Image> optimizada
  s("nimg", fmt([[
<Image
  src="{{{}}}"
  alt="{{{}}}"
  width={{{3:800}}}
  height={{{4:600}}}
  className="{{{}}}"
/>]], { i(1, "/imagen.png"), i(2, "alt"), i(5, "rounded-lg") })),

  -- Route Handler (app/api/*/route.ts)
  s("nroute", fmt([[
import {{ NextResponse }} from 'next/server'

export async function GET() {{
  try {{
    return NextResponse.json({{ {} }})
  }} catch (error) {{
    console.error(error)
    return NextResponse.json(
      {{ error: 'Error interno' }},
      {{ status: 500 }}
    )
  }}
}}]], { i(1, "ok: true") })),

  -- useEffect + fetch
  s("nfetch", fmt([[
const [{} , set{}] = useState<{} | null>(null)

useEffect(() => {{
  fetch('{}')
    .then((res) => res.json())
    .then(set{})
    .catch(console.error)
}}, [])]], {
    i(1, "data"), l_rep(1, true), i(3, "Tipo"),
    i(4, "/api/ruta"), l_rep(1, true),
  })),

  -- Server Action
  s("naction", fmt([[
'use server'

export async function {}(formData: FormData) {{
  {}
}}]], { i(1, "crearAlgo"), i(2, "// lógica") })),
}

M.all = {}
for _, group in ipairs({ M.next_component, M.next_file_helpers }) do
  for ft, _ in pairs(group) do end
end

-- Aplicar a filetypes JS/TS y JSX/TSX
ls.add_snippets(nil, vim.tbl_deep_extend("force", {}, unpack({
  ls.parser and {} or {}, -- placeholder
})))

return {
  next = function()
    for _, snips in ipairs(M.next_component) do table.insert(M.all, snips) end
    for _, snips in ipairs(M.next_file_helpers) do table.insert(M.all, snips) end
  end,
}
