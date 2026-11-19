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
    local ok, monitor = pcall(hl.get_monitor_at, x, y)
    if ok and monitor then return monitor end
    for _, candidate in ipairs(hl.get_monitors()) do
        local width = candidate.width / candidate.scale
        local height = candidate.height / candidate.scale
        if candidate.transform % 2 == 1 then width, height = height, width end
        if x >= candidate.x and x < candidate.x + width and y >= candidate.y and y < candidate.y + height then
            return candidate
        end
    end
    return nil
end

-- Monitor donde está el puntero: es la pantalla en la que el usuario siente que
-- está trabajando. Si no se puede leer (lock, cursor oculto), cae al activo.
local function monitor_under_pointer()
    local ok, position = pcall(hl.get_cursor_pos)
    if ok and position then
        local monitor = monitor_at(position.x, position.y)
        if monitor then return monitor end
    end
    local ok_active, monitor = pcall(hl.get_active_monitor)
    if ok_active then return monitor end
    return nil
end

-- Base del monitor donde está el puntero. Con `hl.get_active_monitor()` el set
-- salía del monitor de la ventana enfocada: mover el mouse a la laptop y tocar
-- SUPER+3 cambiaba el espacio en la otra pantalla.
local function active_base()
    return base_for(monitor_under_pointer())
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

-- Índice local del workspace activo. Acepta el id (número) o el objeto de
-- workspace que devuelve la API (`HL.Workspace`) — que NO es una tabla de Lua
-- sino userdata indexable: por eso se mira `.id` y no `type(...) == "table"` (con
-- eso último local_of(hl.get_active_workspace()) daba siempre nil y el "mismo
-- espacio vuelve al anterior" nunca funcionaba).
local function local_of(workspace)
    if workspace == nil then return nil end
    if type(workspace) == "number" then return to_local(workspace) end
    local id = workspace.id
    if type(id) == "number" then return to_local(id) end
    return nil
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

-- Spotify va al ÚLTIMO espacio del set de la pantalla donde está el puntero.
-- Antes era una regla fija al último espacio de la pantalla "de trabajo": con la
-- vertical enchufada se abría siempre en la vertical, aunque lo abrieras desde la
-- laptop. El espacio destino tiene su regla de monitor (ver monitors.lua), así
-- que se crea en la pantalla correcta aunque no exista todavía.
local function move_spotify(window)
    if window == nil or window.class ~= "Spotify" then return end
    local target = active_base() + SET_SIZE - 1
    hl.dispatch(hl.dsp.window.move({
        window = "address:" .. window.address,
        workspace = tostring(target),
    }))
end

hl.on("window.open", move_spotify)
hl.on("window.class", move_spotify)

-- Reglas que mandan una app a un espacio fijo. Hoy no hay ninguna: Spotify se
-- resuelve por evento (arriba) para que dependa de la pantalla del puntero.
local function apply_window_rules()
end

-- Al desconectar la pantalla externa, Hyprland se trae sus espacios (28..36) a
-- la interna. Esas ventanas quedan en espacios que ningún atajo de la laptop
-- alcanza: la barra, el overview y los atajos sólo conocen 1..9. Por eso, en
-- cuanto la externa desaparece, se mudan a 1..9 repartidas: mismo número si
-- está libre; si no, el más cercano libre; si no hay libres, el que tenga menos
-- ventanas. Nunca se apila todo en un solo espacio.

local function internal_present()
    for _, monitor in ipairs(hl.get_monitors()) do
        if is_internal(monitor.name) then return true end
    end
    return false
end

-- Espacio 1..9 destino para un grupo de ventanas. Puro: recibe la carga actual
-- de cada espacio para poder probarlo sin tocar ventanas.
local function choose_target(index, loads)
    loads = loads or {}
    if (loads[index] or 0) == 0 then return index end
    local best_distance, nearest
    for candidate = 1, SET_SIZE do
        if (loads[candidate] or 0) == 0 then
            local distance = math.abs(candidate - index)
            if best_distance == nil or distance < best_distance then
                best_distance, nearest = distance, candidate
            end
        end
    end
    if nearest ~= nil then return nearest end
    local least
    for candidate = 1, SET_SIZE do
        local load = loads[candidate] or 0
        local distance = math.abs(candidate - index)
        if least == nil or load < least.load
            or (load == least.load and distance < least.distance) then
            least = { load = load, distance = distance, index = candidate }
        end
    end
    return least and least.index or index
end

-- Agrupa las ventanas de la externa por espacio y calcula adónde va cada grupo.
local function plan_migration()
    local loads, groups = {}, {}
    for i = 1, SET_SIZE do loads[i] = 0 end
    for _, window in ipairs(hl.get_windows({ mapped = true })) do
        local workspace = window.workspace
        local id = workspace and workspace.id
        if type(id) == "number" and id > 0 then
            local index = to_local(id)
            if index ~= nil then
                if id >= EXTERNAL_BASE then
                    groups[index] = groups[index] or {}
                    table.insert(groups[index], window.address)
                else
                    loads[index] = loads[index] + 1
                end
            end
        end
    end
    local plan = {}
    for index = 1, SET_SIZE do
        local addresses = groups[index]
        if addresses ~= nil then
            local target = choose_target(index, loads)
            loads[target] = loads[target] + #addresses
            table.insert(plan, { from = index, to = target, addresses = addresses })
        end
    end
    return plan
end

-- Mudanza real. Devuelve el plan como texto ("29->2 (3)") para poder probarlo
-- con dry_run sin mover nada.
local function migrate_external_windows(options)
    options = options or {}
    local report = {}
    if real_monitor_count() >= 2 then return report end  -- la externa sigue: no hay nada que rescatar
    if not internal_present() then return report end      -- clamshell: no hay interna donde mudarlas
    for _, step in ipairs(plan_migration()) do
        report[#report + 1] = string.format("%d->%d (%d)",
            step.from + EXTERNAL_BASE - 1, step.to, #step.addresses)
        if options.dry_run ~= true then
            for _, address in ipairs(step.addresses) do
                hl.dispatch(hl.dsp.window.move({
                    workspace = tostring(step.to),
                    window = "address:" .. address,
                    follow = false,
                }))
            end
        end
    end
    return report
end

-- Espera a que Hyprland termine de mover los espacios de la pantalla que se fue.
local migration_pending = false
local function schedule_migration()
    if migration_pending then return end
    migration_pending = true
    hl.timer(function()
        migration_pending = false
        pcall(migrate_external_windows)
    end, { timeout = 700, type = "oneshot" })
end

hl.on("monitor.removed", schedule_migration)
hl.on("config.reloaded", schedule_migration)

-- Para probar desde `hyprctl repl` sin editar la config.
_G.omarchy = _G.omarchy or {}
_G.omarchy.spaces_choose_target = choose_target
_G.omarchy.spaces_plan = plan_migration
_G.omarchy.spaces_migrate = migrate_external_windows

return {
    PRIMARY_BASE = PRIMARY_BASE,
    EXTERNAL_BASE = EXTERNAL_BASE,
    SET_SIZE = SET_SIZE,
    base_for = base_for,
    active_base = active_base,
    monitor_under_pointer = monitor_under_pointer,
    to_global = to_global,
    to_local = to_local,
    local_of = local_of,
    main_base = main_base,
    main_last = main_last,
    workspace_method = workspace_method,
    apply_window_rules = apply_window_rules,
    choose_target = choose_target,
    plan_migration = plan_migration,
    migrate_external_windows = migrate_external_windows,
    schedule_migration = schedule_migration,
}
