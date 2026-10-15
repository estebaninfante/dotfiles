local SO = os.getenv("HOME").."/.local/share/hypr3d-src/build/hypr3d.so"
local f = io.open("/tmp/h3d_diag.log","w")
local function try(tag)
  local ok, err = pcall(function() hl.plugin.load(SO) end)
  f:write(tag, " ok=", tostring(ok), " err=", tostring(err), " has=", tostring(hl.plugin.hypr3d ~= nil), "\n"); f:flush()
end
try("initial")
hl.on("hyprland.start", function() try("start") end)
