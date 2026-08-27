-- Snippets propios Next.js/React. friendly-snippets cubre el resto
-- (HTML, CSS, tailwind, etc.)
local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

local function define(ft)
  ls.add_snippets(ft, {
    -- Server Component (App Router)
    s("nsc", fmt([[
export default function {1}() {{
  return (
    <{2}>{3}</{2}>
  )
}}]], { i(1, "Componente"), i(2, "div"), i(3) })),

    -- Client Component con estado
    s("ncc", fmt([[
'use client'

import {{ useState }} from 'react'

export default function {1}() {{
  const [{3}, set{3}] = useState({4})
  return (
    <{2}>{5}</{2}>
  )
}}]], { i(1, "Componente"), i(2, "div"), i(3, "estado"), i(4, ""), i(5) })),

    -- Metadata export
    s("nmeta", fmt([[
import type {{ Metadata }} from 'next'

export const metadata: Metadata = {{
  title: '{1}',
  description: '{2}',
}}]], { i(1, "Título"), i(2, "Descripción") })),

    -- <Link>
    s("nlink", fmt([[<Link href="{1}" className="{2}">{3}</Link>]], { i(1, "/"), i(2), i(3) })),

    -- <Image> optimizada
    s("nimg", fmt([[
<Image
  src="{{{1}}}"
  alt="{{{2}}}"
  width={{{3}}}
  height={{{4}}}
  className="{{{5}}}"
/>]], { i(1, "/ruta.png"), i(2, "alt"), i(3, "800"), i(4, "600"), i(5, "rounded-lg") })),

    -- Route Handler (app/api/*/route.ts)
    s("nroute", fmt([[
import {{ NextResponse }} from 'next/server'

export async function GET() {{
  try {{
    return NextResponse.json({{ {1} }})
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
const [{1}, set{1}] = useState<{2} | null>(null)

useEffect(() => {{
  fetch('{3}')
    .then((res) => res.json())
    .then(set{1})
    .catch(console.error)
}}, [])]], { i(1, "data"), i(2, "Tipo"), i(3, "/api/ruta") })),

    -- Server Action
    s("naction", fmt([[
'use server'

export async function {1}(formData: FormData) {{
  {2}
}}]], { i(1, "crearAlgo"), i(2, "// lógica") })),
  })
end

define("typescriptreact")
define("javascriptreact")

-- que apliquen también en .tsx/.jsx
ls.filetype_extend("tsx", { "typescriptreact" })
ls.filetype_extend("jsx", { "javascriptreact" })