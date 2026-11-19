-- Agent Seat (PR omacom/omarchy#15087). Las apps que lanza `omarchy agent seat
-- run` llegan a Hyprland a través del broker del asiento, que nombra cada
-- ventana "agent-<n>.<app id>". Abren en el espacio del asiento
-- (agent-workspaces.lua) sin llevarte, siguen dibujando aunque el espacio esté
-- oculto (para que el agente capture), nunca te roban el foco y llevan borde
-- naranja para no confundirlas con ventanas tuyas.
--
-- Va al final de hyprland.lua, después de todas las reglas de apps: gana la
-- última que matchea y una app del agente elige su propio título (una página
-- llamada "Picture-in-Picture" agarraría la regla de PiP). El marcado matchea
-- además por tag: cuando cambian los tags de una ventana, Hyprland re-aplica
-- sólo las reglas de tags, en orden.
local agent_workspaces = require("agent-workspaces")

local AGENT_CLASS = "agent-[0-9]+(\\..*)?"

agent_workspaces.place("agent-seat-apps", { class = AGENT_CLASS }, true)

o.window(AGENT_CLASS, { tag = "+agent-seat" })
o.window({ tag = "agent-seat" }, {
  render_unfocused = true,
  no_initial_focus = true,
  no_dim = true,
  pin = false,
  border_size = 3,
  border_color = "rgba(ff8a00ff) rgba(ffc266ff) 45deg",
})

return true
