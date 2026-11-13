-- Sets de workspaces por pantalla: 9 espacios por cada una.
--
-- La idea: cada pantalla tiene su propio juego de 9 espacios, y los atajos
-- (SUPER+M/W/V/H/T/N/G/C/R) apuntan a la pantalla que tiene el foco. Así, con
-- la vertical enchufada a la laptop, SUPER+H en la vertical va al espacio H de
-- la vertical y SUPER+H en la laptop va al espacio H de la laptop.
--
-- Cómo se reparten los ids:
--   * la pantalla interna (eDP-*) es dueña de 1..9 SIEMPRE. Es lo de siempre
--     con la laptop sola, así que las reglas de ventanas que apuntan a un
--     número fijo (Spotify, leia, cartridges) no se rompen al desenchufar;
--   * cuando hay más de una pantalla, la externa (la vertical) usa 28..36: los
--     mismos 9 espacios con ids propios. Los números no se ven en ningún lado
--     (ni la barra ni hyprexpo rotulan), así que la sensación es idéntica;
--   * 10 queda para leia/cartridges y 11..20 para `espacios` (agentes). Por eso
--     la segunda pantalla arranca en 28 y no en 10.
--
-- Todo el resto de la config (navigation.lua, la barra, hyprexpo, grid-move)
-- trabaja con el ÍNDICE LOCAL 1..9 y traduce acá: `to_global` para despachar y
-- `local_of` para leer el workspace activo. La regla vive acá y se repite en
-- plugins/eztvn.workspaces/Workspaces.qml (la barra no puede require Lua).
local PRIMARY_BASE = 1
local EXTERNAL_BASE = 28
local SET_SIZE = 9

local function is_internal(name)
    return type(name) == "string" and name:match("^eDP") ~= nil
end

local function is_headless(name)
    return type(name) == "string" and name:match("^HEADLESS") ~= nil
end

-- Salida virtual de pruebas (`pantalla-agente`): no es una pantalla de trabajo,
-- no debe contar como monitor real ni quedar como "la externa" de las reglas.
local function is_agent(name)
    return type(name) == "string" and name:match("^AGENTE") ~= nil
end

-- Sólo cuentan los monitores de verdad: Sunshine crea un HEADLESS-N para
-- streamear y, si contara, el desktop (una sola pantalla) pasaría a tener "dos"
-- y se le moverían todos los espacios a 28..36 en mitad del stream.
local function real_monitor_count()
    local n = 0
    for _, monitor in ipairs(hl.get_monitors()) do
        if not is_headless(monitor.name) and not is_agent(monitor.name) then n = n + 1 end
    end
    return n
end

-- Base (id del primer espacio) de una pantalla. La interna siempre 1; una
-- externa, sólo cuando convive con otra pantalla, 28.
local function base_for(monitor)
    local name = monitor and monitor.name or nil
    if is_internal(name) then return PRIMARY_BASE end
    if real_monitor_count() <= 1 then return PRIMARY_BASE end
    return EXTERNAL_BASE
end

-- Monitor bajo un punto global (coordenadas lógicas del layout).
local function monitor_at(x, y)
    for _, monitor in ipairs(hl.get_monitors()) do
        local width = monitor.width / monitor.scale
        local height = monitor.height / monitor.scale
        if monitor.transform % 2 == 1 then width, height = height, width end
        if x >= monitor.x and x < monitor.x + width and y >= monitor.y and y < monitor.y + height then
            return monitor
        end
    end
    return nil
end

-- Base del monitor DONDE ESTÁ EL PUNTERO: es la pantalla en la que el usuario
-- siente que está trabajando. Con `hl.get_active_monitor()` el set salía del
-- monitor de la ventana enfocada: mover el mouse a la laptop y tocar SUPER+3
-- cambiaba el espacio en la otra pantalla. Si el puntero no se puede leer (lock),
-- cae al monitor activo.
local function active_base()
    local ok, position = pcall(hl.get_cursor_pos)
    if ok and position then
        local monitor = monitor_at(position.x, position.y)
        if monitor then return base_for(monitor) end
    end
    local ok_active, monitor = pcall(hl.get_active_monitor)
    if not ok_active or not monitor then return PRIMARY_BASE end
    return base_for(monitor)
end

local function to_global(index, monitor)
    local base
    if monitor ~= nil then
        base = base_for(monitor)
    else
        base = active_base()
    end
    return base + (index - 1)
end

-- Índice local (1..9) de un id de workspace, o nil si no es de ningún set
-- (espacios de agentes, leia, specials de Moonlight: id negativo).
local function to_local(id)
    if type(id) ~= "number" then return nil end
    if id >= PRIMARY_BASE and id < PRIMARY_BASE + SET_SIZE then return id end
    if id >= EXTERNAL_BASE and id < EXTERNAL_BASE + SET_SIZE then
        return id - EXTERNAL_BASE + 1
    end
    return nil
end

-- Índice local del workspace activo. Acepta el objeto de workspace o el id.
local function local_of(workspace)
    if workspace == nil then return nil end
    if type(workspace) == "table" then return to_local(workspace.id) end
    return to_local(workspace)
end

-- Pantalla "de trabajo": la externa si está, si no la interna. Sobre ella viven
-- los espacios que las reglas fijas de ventanas usan (Spotify en el último).
local function main_base()
    local count = 0
    local external
    for _, monitor in ipairs(hl.get_monitors()) do
        if not is_headless(monitor.name) then
            count = count + 1
            if not is_internal(monitor.name) then external = monitor end
        end
    end
    if count > 1 and external then return base_for(external) end
    return PRIMARY_BASE
end

local function main_last()
    return main_base() + SET_SIZE - 1
end

-- `workspace_method` de hyprexpo: la grilla de cada pantalla se ancla en su
-- primer espacio. El `first 1` suelto es el fallback para un monitor que
-- aparezca antes de que se re-aplique esto.
local function workspace_method()
    local parts = {}
    for _, monitor in ipairs(hl.get_monitors()) do
        parts[#parts + 1] = monitor.name .. " first " .. base_for(monitor)
    end
    parts[#parts + 1] = "first " .. PRIMARY_BASE
    return table.concat(parts, ", ")
end

-- Reglas que mandan una app a un espacio de la pantalla de trabajo. Se
-- re-registran cuando cambian los monitores (la última regla que matchea gana),
-- así Spotify cae en el último espacio de la vertical cuando está enchufada y
-- en el último de la laptop cuando no.
local function apply_window_rules()
    hl.window_rule({ match = { class = "Spotify" }, workspace = tostring(main_last()) })
end

return {
    PRIMARY_BASE = PRIMARY_BASE,
    EXTERNAL_BASE = EXTERNAL_BASE,
    SET_SIZE = SET_SIZE,
    base_for = base_for,
    active_base = active_base,
    to_global = to_global,
    to_local = to_local,
    local_of = local_of,
    main_base = main_base,
    main_last = main_last,
    workspace_method = workspace_method,
    apply_window_rules = apply_window_rules,
}
