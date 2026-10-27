-- Tira: modo de scroll (tipo niri) por workspace, encendido a demanda.
--
-- No es permanente: se prende y se apaga por workspace, en caliente, sin
-- recargar la config de Hyprland (un reload rompe cosas, entre ellas el
-- overview de hyprexpo). Con el modo apagado, el workspace es la grilla de
-- siempre.
--
-- Estado: ~/.local/state/tira.modo (una linea por workspace prendido).
-- Se maneja con el comando `tira` (~/.local/bin/tira).
--
-- Teclas (solo hacen algo en un workspace con el modo prendido):
--   SUPER + ALT + T        prender / apagar el modo en el workspace actual
--   SUPER + rueda abajo/arriba   recorrer la cinta
--   SUPER + ALT + F        pantalla completa que NO se rompe al scrollear
--   SUPER + ALT + G        expandir la columna activa
--   SUPER + ALT + I        encajar la columna activa en vista
--   SUPER + ALT + C        congelar / descongelar el scroll
--   SUPER + ALT + SHIFT + O / U   mover la ventana una columna atras/adelante
--   SUPER + O / U / ñ / E  mover el foco (el layout lo sigue solo)
--
-- Ojo con hyprexpo: su grilla dibuja en negro las miniaturas de los workspaces
-- que estan en modo tira. El resto se ve normal. Es una limitacion del plugin.
-- Y dentro de la tira no uses SUPER+F (el fullscreen de siempre tapa la cinta):
-- para eso esta SUPER+ALT+F.

local HOME  = os.getenv("HOME") or ""
local STATE = HOME .. "/.local/state/tira.modo"

local DEFAULT_DIRECTION = "down"

local tira = {
    direction  = DEFAULT_DIRECTION,
    workspaces = {},   -- id (string) -> true
}

local function id_of(workspace)
    if type(workspace) == "table" then
        workspace = workspace.id
    end
    if workspace == nil then
        return nil
    end
    local id = tonumber(workspace)
    if not id or id <= 0 then
        return nil          -- los special workspaces (negativos) quedan afuera
    end
    return tostring(id)
end

local function read_state()
    local file = io.open(STATE, "r")
    if not file then
        return
    end
    local workspaces = {}
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key == "direction" and value ~= "" then
            tira.direction = value
        elseif key == "workspace" and value ~= "" then
            workspaces[value] = true
        end
    end
    file:close()
    tira.workspaces = workspaces
end

local function write_state()
    local ids = {}
    for id in pairs(tira.workspaces) do
        ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)

    local file = io.open(STATE, "w")
    if not file then
        return
    end
    file:write("direction=" .. tira.direction .. "\n")
    for _, id in ipairs(ids) do
        file:write("workspace=" .. id .. "\n")
    end
    file:close()
end

-- Ajustes del layout de scroll. Se aplican recien cuando un workspace entra
-- en modo tira, no antes: con el modo apagado la config queda como estaba.
local function configure_layout()
    hl.config({
        scrolling = {
            column_width             = 1.0,
            fullscreen_on_one_column = true,
            follow_focus             = true,
            focus_fit_method         = 1,
            follow_min_visible       = 0.4,
            wrap_focus               = false,
            explicit_column_widths   = "0.5, 0.667, 1.0",
        },
    })
end

local function set_rule(id)
    if tira.workspaces[id] then
        configure_layout()
        hl.workspace_rule({
            workspace   = id,
            layout      = "scrolling",
            layout_opts = { direction = tira.direction },
        })
    else
        hl.workspace_rule({ workspace = id, layout = "dwindle" })
    end
end

local function apply_all()
    for id in pairs(tira.workspaces) do
        set_rule(id)
    end
end

local function notify(text)
    hl.notification.create({ text = text, duration = 1400 })
end

-- Funcion global: la llama el comando `tira` por hyprctl eval, y tambien las
-- teclas. Todo el estado vive aca adentro.
function TiraModo(accion, valor, workspace)
    accion = accion or "toggle"

    if accion == "estado" then
        local ids = {}
        for id in pairs(tira.workspaces) do
            ids[#ids + 1] = id
        end
        table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
        return { direccion = tira.direction, workspaces = ids }
    end

    if accion == "direccion" then
        tira.direction = valor or DEFAULT_DIRECTION
        apply_all()
        write_state()
        return tira.direction
    end

    local current = id_of(workspace) or id_of(hl.get_active_workspace())

    if accion == "off" then
        local anteriores = tira.workspaces
        tira.workspaces = {}
        for id in pairs(anteriores) do
            set_rule(id)
        end
        if current then
            set_rule(current)
        end
        write_state()
        notify("Tira apagada")
        return false
    end

    if not current then
        notify("Tira: no encontre el workspace activo")
        return false
    end

    local encender
    if accion == "on" then
        encender = true
    elseif accion == "toggle" then
        encender = not tira.workspaces[current]
    else
        notify("Tira: accion desconocida (" .. tostring(accion) .. ")")
        return false
    end

    tira.workspaces[current] = encender or nil
    set_rule(current)
    write_state()
    notify(encender and ("Tira: modo scroll en el workspace " .. current)
                     or ("Tira: workspace " .. current .. " de vuelta en grilla"))
    return encender
end

read_state()
pcall(apply_all)

-- Si Hyprland recarga la config (SUPER+SHIFT+R) o arranca, las reglas de
-- workspace se rearman con el estado guardado: el modo no se pierde.
hl.on("hyprland.start", function() pcall(apply_all) end)
hl.on("config.reloaded", function() pcall(apply_all) end)

local function in_mode()
    local id = id_of(hl.get_active_workspace())
    return id ~= nil and tira.workspaces[id] == true
end

local function layout_in_mode(message)
    if not in_mode() then
        return
    end
    hl.dispatch(hl.dsp.layout(message))
end

-- Rueda del mouse / dos dedos del trackpad: recorre la cinta.
hl.bind("SUPER + mouse_down", function() layout_in_mode("move +col") end,
        { repeating = true, description = "Tira: avanzar en la cinta" })
hl.bind("SUPER + mouse_up", function() layout_in_mode("move -col") end,
        { repeating = true, description = "Tira: retroceder en la cinta" })

hl.bind("SUPER + ALT + T", function() TiraModo("toggle") end,
        { description = "Tira: prender/apagar el modo scroll" })

hl.bind("SUPER + ALT + F", function()
    helpers.focus_under_cursor()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", layout_aware = true }))
end, { description = "Tira: pantalla completa que no rompe el scroll" })

hl.bind("SUPER + ALT + G", function() layout_in_mode("fit expand") end,
        { repeating = true, description = "Tira: expandir columna" })
hl.bind("SUPER + ALT + I", function() layout_in_mode("fit_into_view") end,
        { description = "Tira: encajar columna en vista" })
hl.bind("SUPER + ALT + C", function() layout_in_mode("inhibit_scroll") end,
        { description = "Tira: congelar scroll" })
hl.bind("SUPER + ALT + SHIFT + O", function() layout_in_mode("move -col") end,
        { repeating = true, description = "Tira: mover columna atras" })
hl.bind("SUPER + ALT + SHIFT + U", function() layout_in_mode("move +col") end,
        { repeating = true, description = "Tira: mover columna adelante" })

return true
