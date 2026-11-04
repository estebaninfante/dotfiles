require("base.bindcollect")  -- debe ir ANTES de cualquier bind (lo usa dictado-submap)
require("env")
require("monitors")
require("input")
require("looknfeel")
require("gaps")
require("layerrules")
require("animations")
require("autostart")

require("plugins.hyprexpo")
require("plugins.hypr3d")
require("navigation")
require("visionhub-typing")

require("windowrules")
require("poco-f3")
require("whatsapp-call")
require("windowhelpers")
require("bindings")
require("moonlight")
require("ohm")
-- Tira: workspace de scroll (pantallas completas en columnas). Estado en
-- ~/.local/state/tira.conf; se maneja con el comando `tira`.
require("tira")

-- Después de TODOS los binds: el submap "dictado" replaysa los globales para
-- que la transcripción no desactive los atajos.
require("dictado-submap")
