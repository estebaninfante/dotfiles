-- Workspace del Agent Seat (PR omacom/omarchy#15087): las apps que el agente
-- maneja con su propio puntero y teclado abren en este espacio, no en el tuyo.
-- Adaptado de default/hypr/agent-workspaces.lua de la rama `agent-seat`.
--
-- Cambiarlo: require("agent-workspaces").set({ seat = 20 })
-- Uno por monitor: require("agent-workspaces").set({ per_monitor = 10 })
--   (los monitores se cuentan de izquierda a derecha; se puede fijar el orden
--    con monitors = { "HDMI-A-1", "eDP-2" }).
--
-- En esta máquina: 20 está libre (eDP-2 usa 1-9, HDMI-A-1 usa 31-36).

local M = {}

M.settings = {
  seat = 20,
  per_monitor = 0,
  monitors = {},
}

-- Reglas con nombre: reescribirlas reemplaza en vez de apilar, así el workspace
-- sigue al monitor en el que abrís la app.
local placements = {}

local function monitor_index(active)
  if M.settings.per_monitor == 0 or not active then
    return 0
  end

  for index, name in ipairs(M.settings.monitors) do
    if name == active.name then
      return index - 1
    end
  end

  -- Monitores no listados siguen a los listados, contados de izquierda a derecha.
  local listed = {}
  for _, name in ipairs(M.settings.monitors) do
    listed[name] = true
  end
  -- Se cuenta con # y no con ipairs: el menú de atajos carga este config con un
  -- hl de mentira cuyos campos son todos sí mismos.
  local monitors = hl.get_monitors() or {}
  local rest = {}
  for index = 1, #monitors do
    local monitor = monitors[index]
    if not listed[monitor.name] then
      table.insert(rest, monitor)
    end
  end
  table.sort(rest, function(a, b)
    if a.x ~= b.x then
      return a.x < b.x
    end
    return a.y < b.y
  end)
  for index, monitor in ipairs(rest) do
    if monitor.name == active.name then
      return #M.settings.monitors + index - 1
    end
  end
  return 0
end

-- El espacio del asiento en un monitor, el enfocado si no se pasa ninguno.
function M.workspace(monitor)
  return M.settings.seat + monitor_index(monitor or hl.get_active_monitor()) * M.settings.per_monitor
end

local function apply()
  local workspace = tostring(M.workspace())
  for name, placement in pairs(placements) do
    hl.window_rule({
      name = name,
      match = placement.match,
      workspace = placement.silent and workspace .. " silent" or workspace,
    })
  end
end

-- Manda al espacio del asiento las ventanas que matcheen `match`. Silencioso =
-- no te cambia de workspace; si no, la ventana te lleva.
function M.place(name, match, silent)
  placements[name] = { match = match, silent = silent }
  apply()
end

function M.set(settings)
  for key, value in pairs(settings) do
    M.settings[key] = value
  end
  apply()
end

hl.on("monitor.focused", apply)
hl.on("monitor.added", apply)
hl.on("monitor.removed", apply)

return M
