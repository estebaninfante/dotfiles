hl.layer_rule({
    match = { namespace = "swaync" },
    blur = true
})

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

return true
