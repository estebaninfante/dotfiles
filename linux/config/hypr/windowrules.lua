local variables = require("base.variables")

hl.window_rule({ match = { class = "swappy" }, no_anim = true })

hl.window_rule({ match = { class = ".*" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "kitty" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "herdr" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "brave-browser" }, opacity = "1.0 1.0" })
hl.window_rule({ match = { float = true }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "discord", float = true }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "^foldertinder$" }, workspace = "special:ft silent", no_initial_focus = 1, no_anim = true, border_size = 0, no_blur = 1, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "com.stremio.Stremio" }, idle_inhibit = "always" })
hl.window_rule({ match = { class = "leia" }, workspace = "10" })
hl.window_rule({ match = { class = "leia" }, fullscreen = 1 })
hl.window_rule({ match = { class = "libreoffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "soffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "Spotify" }, workspace = "9" })
hl.window_rule({ match = { class = "swayosd-server" }, float = 1 })
hl.window_rule({ match = { class = "swayosd-server" }, move = "1% 40%" })
hl.window_rule({ match = { class = "swayosd-server" }, size = "200 20" })
hl.window_rule({ match = { class = "swayosd-server" }, border_size = 0 })
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, max_size = "1260 560" })
if variables.machine == "desktop" then
    hl.window_rule({ match = { class = "handy", title = "Recording" }, float = 1, no_initial_focus = 1, no_blur = 1, border_size = 0 })
end
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, workspace = "10" })
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, fullscreen = 1 })
hl.window_rule({ match = { class = "ssh-desktop" }, opacity = "1.0 1.0", border_color = "rgba(00ff99f2)" })

return true
