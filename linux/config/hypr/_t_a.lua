pcall(function() hl.plugin.load(os.getenv("HOME").."/.local/share/hypr3d-src/build/hypr3d.so") end)
if hl.plugin.hypr3d then hl.bind("SUPER + F12", hl.plugin.hypr3d.toggle) end
