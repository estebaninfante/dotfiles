pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: themeService

    property bool themeLight: false

    function refresh() {
        themeStateRead.running = false;
        themeStateRead.running = true;
    }

    function toggle() {
        themeToggleScript.command = ["bash", "-c", "~/.local/bin/theme-toggle.sh toggle"];
        themeToggleScript.running = false;
        themeToggleScript.running = true;
    }

    Process {
        id: themeStateRead
        command: ["bash", "-c", "readlink \"$HOME/dotfiles/linux/config/kitty/active-theme.conf\" | grep -o 'theme-[a-z]*'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: themeService.themeLight = this.text.trim().indexOf("light") !== -1
        }
    }

    Process {
        id: themeToggleScript
        command: ["true"]
        running: false
        onExited: themeService.refresh()
    }
}