-- Autocompletado IA (minuet) via Groq, estilo Copilot no intrusivo:
-- ghost text tras pausa breve, nunca inserta sin confirmar.
-- Aceptar: <Tab> · línea: <M-L> · descartar: <C-]> · navegar: <M-]> / <M-[>
return {
  "milanglacier/minuet-ai.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    -- Key Groq vive en ~/.local/state/opencode/notify-groq-key (chmod 600,
    -- NUNCA en el repo). Se exporta como env var solo en esta sesión de nvim.
    local f = io.open(vim.fn.expand("~/.local/state/opencode/notify-groq-key"), "r")
    if f then
      local key = (f:read("*l") or ""):gsub("%s+", "")
      f:close()
      if key ~= "" then
        vim.env.GROQ_API_KEY = key
      end
    end

    require("minuet").setup({
      throttle = 900, -- ms entre peticiones automáticas
      provider = "openai_compatible",
      provider_options = {
        openai_compatible = {
          api_key = "GROQ_API_KEY",
          name = "Groq",
          end_point = "https://api.groq.com/openai/v1/chat/completions",
          model = "llama-3.3-70b-versatile", -- rápido; si va lento: llama-3.1-8b-instant
          optional = {
            max_tokens = 128, -- sugerencias cortas, menos intrusivas
            top_p = 0.9,
          },
        },
      },
      virtualtext = {
        enable = true,
        auto_trigger = true,
        auto_trigger_ft = { "*" }, -- requerido: sin esto el auto-trigger nunca se activa
        show_on_completion_menu = false, -- oculto cuando abre menú nvim-cmp
        keymap = {
          accept = "<Tab>",
          accept_line = "<M-L>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
    })
  end,
}
