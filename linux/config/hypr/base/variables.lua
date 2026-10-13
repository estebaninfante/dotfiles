local home = os.getenv("HOME")
local machine_file = io.open(home .. "/.config/machine-type", "r")
local machine = machine_file and machine_file:read("*a"):match("^%s*(.-)%s*$") or "laptop"
if machine_file then machine_file:close() end

return {
    main_mod = "SUPER",
    terminal = "kitty",
    file_manager = "dolphin",
    menu = "ulauncher",
    machine = machine,
    workspace_keys = { "M", "W", "V", "H", "T", "N", "G", "C", "R", "S" },
}
