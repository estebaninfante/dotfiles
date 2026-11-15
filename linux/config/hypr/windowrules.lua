local variables = require("base.variables")

hl.window_rule({ match = { class = "swappy" }, no_anim = true })

-- Llamada de WhatsApp (la ventanita emergente que abre el PWA de Brave al
-- entrar a una llamada). Queda flotante y pinned (visible en todos los
-- workspaces y arriba del mosaico) en la esquina superior derecha, sin borde,
-- sin blur y opaca. El tamaño arranca en 9:16 y ~/.local/bin/whatsapp-call-fit
-- lo ajusta al aspecto real del video (ver whatsapp-call.lua).
hl.window_rule({
    match = { class = "[Ww]hatsapp", title = "[Ll]lamada de WhatsApp$" },
    float = true,
    pin = true,
    size = { 360, 520 },
    move = { "(monitor_w-window_w-24)", "40" },
    border_size = 0,
    rounding = 8,
    no_blur = 1,
    opacity = "1.0 1.0",
})

-- Poco F3 por scrcpy: columna tipo teléfono en el borde derecho, de alto
-- completo. El tamaño/posición final lo calcula poco-f3.lua según el monitor;
-- acá sólo se fija que nazca flotante, pinned y sin adornos.
hl.window_rule({
    match = { class = "^scrcpy$" },
    float = true,
    pin = true,
    border_size = 0,
    rounding = 0,
    no_blur = 1,
    no_shadow = 1,
    opacity = "1.0 1.0",
})

-- El salvapantallas de Omarchy corre en foot (el terminal por defecto), y foot
-- anuncia su app-id recién después del primer map: la regla por `class` de
-- default/hypr/apps/system.lua no le pega, así que quedaba como una ventana tiled
-- en vez de a pantalla completa. `initial_class` sí matchea a tiempo.
hl.window_rule({ match = { initial_class = "^org\\.omarchy\\.screensaver$" }, fullscreen = true, float = true })

hl.window_rule({ match = { class = ".*" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "kitty" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "herdr" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "brave-browser" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { float = true }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "discord", float = true }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "^foldertinder$" }, workspace = "special:ft silent", no_initial_focus = 1, no_anim = true, border_size = 0, no_blur = 1, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "com.stremio.Stremio" }, idle_inhibit = "always" })
hl.window_rule({ match = { class = "leia" }, workspace = "10" })
hl.window_rule({ match = { class = "leia" }, fullscreen = 1 })
hl.window_rule({ match = { class = "libreoffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "soffice.*" }, workspace = "empty" })
-- Spotify: al último espacio de la pantalla de trabajo, que depende de qué
-- pantallas haya (9 con una sola, 36 con la vertical enchufada). Esa regla la
-- registra base/workspaces.lua y se re-registra al enchufar/desenchufar.
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, max_size = "1260 560" })
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, workspace = "10" })
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, fullscreen = 1 })
hl.window_rule({ match = { class = "ssh-peer" }, opacity = "1.0 1.0", border_color = "rgba(00ff99f2)" })

-- Acrílico: WhatsApp (PWA de Brave) y Spotify. Van DESPUÉS del catch-all
-- `class = ".*" opacity 1.0` porque la última regla que matchea gana. La
-- transparencia se ve difuminada por decoration:blur (global); 0.56 no tiene
-- windowrule `blur`. Activo 0.92 = 8% de fondo visible, inactivo 0.85.
hl.window_rule({ match = { class = "^brave-web\\.whatsapp\\.com__-Default$" }, opacity = "0.92 0.85" })
hl.window_rule({ match = { class = "^Spotify$" }, opacity = "0.92 0.85" })

-- Modo ahorro extremo (power-extreme.sh): sin blur, la transparencia solo
-- suma mezcla en el compositor. Esta regla va al final y fuerza opaca toda
-- ventana (gana sobre el acrílico de arriba); el script la habilita/deshabilita
-- en caliente con `hyprctl eval` (omarchy.apply_power_opacity), leyendo el flag
-- del modo. Con el flag ausente nace deshabilitada y mandan las reglas de
-- siempre.
local EXTREME_FLAG = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) ..
    "/power-extreme/on"

local function power_extreme_active()
    local handle = io.open(EXTREME_FLAG, "r")
    if not handle then return false end
    handle:close()
    return true
end

local opaque_rule = hl.window_rule({ match = { class = ".*" }, opacity = "1.0 1.0" })

_G.omarchy = _G.omarchy or {}
_G.omarchy.apply_power_opacity = function()
    local active = power_extreme_active()
    opaque_rule:set_enabled(active)
    return active and "opaque" or "acrylic"
end
_G.omarchy.apply_power_opacity()

-- Historial de dictado (Super+Ctrl+I): ventana flotante y centrada.
hl.window_rule({
  match = { class = "^org\\.omarchy\\.dictado-historial$" },
  float = true,
  center = true,
  size = { 1100, 700 },
})

-- Va al final a propósito: las reglas que dependen de qué pantallas hay se
-- registran después de las fijas (la última que matchea gana).
require("base.workspaces").apply_window_rules()

return true
