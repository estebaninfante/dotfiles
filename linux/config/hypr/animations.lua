local function animations_enabled()
    local handle = io.open(os.getenv("HOME") .. "/.local/state/omarchy/animations-enabled", "r")
    if handle then
        local value = handle:read("*l")
        handle:close()
        if value == "0" then return false end
        if value == "1" then return true end
    end
    return true
end

hl.config({
    animations = {
        enabled = animations_enabled()
    }
})

hl.curve("expoSmooth", {
    type = "bezier",
    points = { { 0.16, 1.0 }, { 0.30, 1.0 } }
})

hl.animation({
    leaf = "global",
    enabled = true,
    speed = 8,
    bezier = "default"
})

-- windowsMove es la hoja que Hyprland usa para el resize/movimiento de ventanas,
-- incluido el cambio a fullscreen. La apagamos para que el fullscreen (por ej.
-- al ciclar medios con SUPER+TAB) sea inmediato y no se anime.
hl.animation({
    leaf = "windowsMove",
    enabled = false
})

hl.curve("expoOpen", {
    type = "bezier",
    points = { { 0.22, 0.61 }, { 0.36, 1.0 } }
})

hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 4,
    bezier = "expoOpen"
})

hl.animation({
    leaf = "specialWorkspace",
    enabled = false
})

hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = false
})

hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = false
})

hl.config({
    misc = {
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        on_focus_under_fullscreen = 1,
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true
    }
})

hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 4,
    bezier = "expoSmooth",
    style = "slide"
})

hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4,
    bezier = "default",
    style = "slide"
})

hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2,
    bezier = "default",
    style = "slide"
})

hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 6,
    bezier = "default",
    style = "popin"
})
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 6,
    bezier = "default",
    style = "popin"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 6,
    bezier = "default",
    style = "popin"
})
-- El cambio a fullscreen también dispara fundidos que no son de tamaño:
-- las otras ventanas del workspace y las capas (la barra) se desvanecen con
-- fadeIn / fadeLayersIn / fadeLayersOut. Los apagamos para que el cambio sea
-- instantáneo. La apertura de ventanas sigue animándose con windowsIn (slide).
hl.animation({ leaf = "fadeIn", enabled = false })

hl.animation({
    leaf = "fadeLayersIn",
    enabled = false
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = false
})

return true
