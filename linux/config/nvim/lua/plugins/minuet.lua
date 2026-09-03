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

    if not vim.env.GROQ_API_KEY then
      vim.notify("minuet: GROQ_API_KEY not found, AI completion disabled", vim.log.levels.WARN)
      return
    end

    require("minuet").setup({
      throttle = 12000, -- 12s entre auto-request: tasa libre Groq es 8000 TPM (~5 req x 1400 tok)
      n = 2048, -- recorta contexto del buffer (chars): cada request usa ~700 tokens en vez de 1400
      provider = "openai_compatible",
      provider_options = {
        openai_compatible = {
          api_key = "GROQ_API_KEY",
          name = "Groq",
          end_point = "https://api.groq.com/openai/v1/chat/completions",
          model = "openai/gpt-oss-20b", -- barato y rápido vs qwen3.8-27b (casi frontera); ultrabarato: llama-3.1-8b-instant
          stream = false, -- Groq no parsea streaming en minuet (llega vacío); non-stream funciona
          optional = {
            max_tokens = 128, -- sugerencias cortas, menos intrusivas
            top_p = 0.9,
            reasoning_effort = "low", -- gpt-oss es reasoning: sin esto todo el presupuesto se va a razonar y content llega vacío
          },
        },
      },
      virtualtext = {
        show_on_completion_menu = false, -- oculto cuando abre menú nvim-cmp
        auto_trigger_ft = { "*" }, -- ghost text automático; toggle con <leader>ia
        keymap = {
          accept = "<C-j>", -- Tab manejado en keymaps.lua (unificado)
          accept_line = "<M-L>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
    })
    -- Toggle auto-trigger (persiste como var buffer-local hasta cambiar de buffer)
    vim.keymap.set("n", "<leader>ia", require("minuet.virtualtext").action.toggle_auto_trigger,
      { desc = "Toggle autocompletado IA" })
  end,
}
