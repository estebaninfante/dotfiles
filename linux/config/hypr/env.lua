local variables = require("base.variables")

hl.config({
    xwayland = {
        force_zero_scaling = true
    }
})

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
if variables.machine == "desktop" then
    hl.env("GDK_SCALE", "1")
else
    hl.env("GDK_SCALE", "2")
end
hl.env("PATH", os.getenv("HOME") .. "/.local/bin:" .. os.getenv("PATH"))
hl.env("XDG_DATA_HOME", os.getenv("HOME") .. "/.local/share")
if variables.machine == "desktop" then
    hl.env("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
    hl.env("HANDY_NO_GTK_LAYER_SHELL", "1")
end

return true
