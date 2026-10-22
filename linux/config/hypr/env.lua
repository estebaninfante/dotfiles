local variables = require("base.variables")

hl.config({
    xwayland = {
        force_zero_scaling = true
    }
})

-- CURSOR: Bibata Modern Ice (blanco con borde negro, se lee en cualquier fondo)
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "28")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "28")

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

-- Modo ahorro extremo (power-extreme.sh, docs/energia-laptop-82y5.md §8): si la
-- sesión arranca con el modo activo, el compositor usa solo la iGPU y los
-- clientes cargan EGL/GLX/Vulkan de Mesa. Así nadie abre la NVIDIA y la dGPU
-- suspende (≈8-10 W). HDMI y DP-1 cuelgan de la dGPU: no andan en esa sesión.
-- AQ_DRM_DEVICES separa con ":", por eso se resuelve el by-path a /dev/dri/cardN.
if variables.machine ~= "desktop" then
    local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
    local flag = io.open(state .. "/power-extreme/on", "r")
    if flag then
        flag:close()
        local ok, p = pcall(io.popen, "readlink -f /dev/dri/by-path/pci-0000:05:00.0-card 2>/dev/null")
        local igpu = ok and p and p:read("*l") or ""
        if ok and p then p:close() end
        if igpu:match("^/dev/dri/card%d+$") then
            hl.env("AQ_DRM_DEVICES", igpu)
            hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
            hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
            hl.env("VK_DRIVER_FILES", "/usr/share/vulkan/icd.d/radeon_icd.json")
        end
    end
end

return true
