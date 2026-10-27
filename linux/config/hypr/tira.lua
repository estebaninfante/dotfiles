-- Tira: un workspace como una tira de "pantallas completas".
--
-- La idea: en vez de repartir el monitor entre la app y los agentes, el
-- workspace se vuelve una cinta donde cada columna ocupa la pantalla entera.
-- Ves tu app llena, scrolleás y aparecen las columnas de al lado, en el MISMO
-- workspace y sin cerrar nada.
--
-- Estado (lo escribe ~/.local/bin/tira, no editar a mano):
--   ~/.local/state/tira.conf
--     workspace=5        numero de workspace de la tira
--     layout=scrolling   scrolling | off   (off = ese workspace queda en grilla)
--     direction=down     down | up | right | left   (eje en que crece la cinta)
--
-- Con direction=down la cinta crece hacia abajo: cada fila es una pantalla y
-- se scrollea en el eje vertical (rueda/trackpad), que es lo natural. Con
-- "right" crece hacia el costado, estilo niri.
--
-- Teclas (solo mientras la tira esta activa):
--   SUPER + O / U / ñ / E   mover el foco (el layout lo sigue solo)
--   SUPER + ALT + F         pantalla completa que NO se rompe al scrollear
--   SUPER + ALT + G         expandir la columna activa
--   SUPER + ALT + I         encajar la columna activa en vista
--   SUPER + ALT + C         congelar/descongelar el scroll del workspace
--   SUPER + ALT + SHIFT + O / U   mover la ventana una columna atras/adelante
--
-- Ojo: dentro de la tira NO uses SUPER+F (el fullscreen de siempre): tapa la
-- cinta entera y te deja sin scroll. Para eso esta SUPER+ALT+F, que usa el
-- fullscreen propio del layout.

local helpers = require("windowhelpers")

local HOME = os.getenv("HOME") or ""
local STATE = HOME .. "/.local/state/tira.conf"

local DEFAULTS = {
    workspace = "5",
    layout    = "scrolling",
    direction = "down",
}

local function read_state()
    local state = {}
    for key, value in pairs(DEFAULTS) do
        state[key] = value
    end

    local file = io.open(STATE, "r")
    if not file then
        return state
    end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key and value ~= "" then
            state[key] = value
        end
    end
    file:close()
    return state
end

local state = read_state()

if state.layout ~= "scrolling" then
    return { active = false, workspace = state.workspace }
end

hl.config({
    scrolling = {
        -- Cada columna ocupa el monitor entero: una ventana sola = pantalla
        -- completa sin tener que pedir fullscreen.
        column_width             = 1.0,
        fullscreen_on_one_column = true,
        follow_focus             = true,
        focus_fit_method         = 1,     -- "fit": encaja, no centra
        follow_min_visible       = 0.4,
        wrap_focus               = false, -- la cinta tiene principio y final
        explicit_column_widths   = "0.5, 0.667, 1.0",
    },
})

hl.workspace_rule({
    workspace   = state.workspace,
    layout      = "scrolling",
    layout_opts = { direction = state.direction },
})

local main_mod = "SUPER"

-- Pantalla completa del layout: al scrollear, la ventana sigue fullscreen en su
-- columna en vez de des-fullscreenarse (layout_aware).
hl.bind(main_mod .. " + ALT + F", function()
    helpers.focus_under_cursor()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", layout_aware = true }))
end, { description = "Tira: pantalla completa que no rompe el scroll" })

hl.bind(main_mod .. " + ALT + G", hl.dsp.layout("fit expand"), { description = "Tira: expandir columna" })
hl.bind(main_mod .. " + ALT + I", hl.dsp.layout("fit_into_view"), { description = "Tira: encajar columna en vista" })
hl.bind(main_mod .. " + ALT + C", hl.dsp.layout("inhibit_scroll"), { description = "Tira: congelar scroll" })

hl.bind(main_mod .. " + ALT + SHIFT + O", hl.dsp.layout("move -col"), { repeating = true, description = "Tira: mover columna atras" })
hl.bind(main_mod .. " + ALT + SHIFT + U", hl.dsp.layout("move +col"), { repeating = true, description = "Tira: mover columna adelante" })

return { active = true, workspace = state.workspace, direction = state.direction }
