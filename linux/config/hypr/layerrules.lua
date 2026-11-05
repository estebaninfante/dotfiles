hl.layer_rule({
    match = { namespace = "wayfreeze" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "selection" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "hyprpicker" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "omarchy-menu" },
    blur = true,
    no_anim = true,
    animation = "none"
})

-- Overlay de PrintScreen: debe aparecer y desaparecer instantáneo, sin
-- animación de capa (el contenido ya viene congelado).
hl.layer_rule({
    match = { namespace = "capture-menu" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "hypr-outline-menu" },
    no_anim = true,
    animation = "none"
})

-- Overlay del dictado: franja al pie con subtítulos en vivo. Se mapea una vez
-- y se queda; la entrada/salida la hace el fade del QML (sin popin del compositor).
hl.layer_rule({
    match = { namespace = "dictado-overlay" },
    no_anim = true,
    animation = "none"
})

-- Transiciones de enlace (Moonlight/Sunshine y lan-mouse): la animación la
-- hace el QML; una animación de capa encima retrasa o se come la escena.
hl.layer_rule({
    match = { namespace = "eztvn-enlace" },
    no_anim = true,
    animation = "none"
})

return true
