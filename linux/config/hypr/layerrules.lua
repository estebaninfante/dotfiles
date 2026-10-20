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

hl.layer_rule({
    match = { namespace = "hypr-outline-menu" },
    no_anim = true,
    animation = "none"
})

-- Omar: la píldora y la franja se mapean/desmapean al abrir y cerrar. El
-- compositor les aplicaba la animación de capas (`layersIn/Out` = popin) y se
-- veían entrar con zoom. El fade lo hace el QML: acá no va ninguna animación.
hl.layer_rule({
    match = { namespace = "omar-pill" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "omar-glow" },
    no_anim = true,
    animation = "none"
})

return true
