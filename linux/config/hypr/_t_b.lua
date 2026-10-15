pcall(function() hl.plugin.load(os.getenv("HOME").."/.local/share/hypr3d-src/build/hypr3d.so") end)
if hl.plugin.hypr3d then hl.plugin.hypr3d.config({ world = { grid = false }, player = { flying = true } }) end
