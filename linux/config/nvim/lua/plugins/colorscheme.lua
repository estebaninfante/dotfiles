return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    config = function()
      -- Tema sigue al modo global (canonico: active-theme.conf de kitty,
      -- que es symlink al repo). 'dawn' = variante CLARA calida (kitty crema
      -- #FDF8F0), 'main' = OSCURA (kitty #161513). Un watcher recarga en vivo
      -- al togglear sin reiniciar nvim.
      local ACTIVE = "$HOME/dotfiles/linux/config/kitty/active-theme.conf"

      local function theme_mode()
        local link = vim.fn.systemlist("readlink " .. vim.fn.fnameescape(vim.fn.expand(ACTIVE)))[1] or ""
        if link:find("light") then return "light" end
        return "dark" -- por defecto oscuro
      end

      local function apply_theme()
        local light = theme_mode() == "light"
        require("rose-pine").setup({
          variant = light and "dawn" or "main",
          dark_variant = "main",
          bold_vert_split = false,
          dim_nc_background = true, -- fondo de ventana inactiva atenuado
          disable_background = false,
          disable_float_background = false,
          styles = {
            bold = true,
            italic = false, -- astigmatismo: nada de itálicas
            transparency = false,
          },
          highlight_groups = {
            CursorLine = { bg = light and "#f2ede3" or "#1b1a18" },
            Visual = { bg = light and "#e0dacf" or "#2b2a26" },
          },
        })
        vim.cmd("colorscheme rose-pine-" .. (light and "dawn" or "main"))
      end

      apply_theme()

      -- Watcher: recarga tema cuando cambia active-theme.conf (symlink swap)
      local kitty_dir = vim.fn.expand("$HOME/dotfiles/linux/config/kitty")
      local watcher = vim.loop.new_fs_event()
      if watcher then
        local function restart()
          watcher:stop()
          apply_theme()
          watcher:start(kitty_dir, "active-theme.conf", {}, vim.schedule_wrap(restart))
        end
        watcher:start(kitty_dir, "active-theme.conf", {}, vim.schedule_wrap(restart))
        vim.api.nvim_create_autocmd("VimLeavePre", { callback = function()
          watcher:stop()
        end })
      end
    end,
  },
}
