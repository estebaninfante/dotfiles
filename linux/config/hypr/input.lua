local variables = require("base.variables")

hl.config({
    general = {
        resize_on_border = true
    },
    input = {
        kb_layout = "dvk_prog,es,us",
        kb_variant = "basic,,",
        -- Sin "caps:none": la Caps Lock fisica ya la remapea keyd a Super
        -- (/etc/keyd/default.conf), asi que aca hace falta que Caps_Lock siga
        -- siendo una tecla real para poder alternar el estado con SUPER+ESCAPE.
        kb_options = "",
        follow_mouse = 1,
        mouse_refocus = true,
        sensitivity = 0
    }
})

hl.device({
    name = "uinput-unifiedremote",
    kb_layout = "us",
    kb_variant = ""
})
hl.device({
    name = "uinput-unifiedremote-1",
    kb_layout = "us",
    kb_variant = ""
})

if variables.machine == "laptop" then
    hl.config({
        input = {
            touchpad = {
                disable_while_typing = true,
                tap_to_click = true,
                clickfinger_behavior = true,
                tap_and_drag = false,
                drag_lock = false,
                natural_scroll = true,
                scroll_factor = 0.5
            }
        }
    })
    hl.device({
        name = "elan06fa:00-04f3:3280-mouse",
        enabled = false
    })
    hl.device({
        name = "elan06fa:00-04f3:3280-touchpad",
        enabled = true
    })
end

return true
