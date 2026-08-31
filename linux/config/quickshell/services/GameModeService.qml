pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: gameModeService

    property bool gameModeActive: false   // expande root a fullscreen
    property bool gameShown: false        // fase de fade-in del overlay
    property bool gameClosing: false      // fase de fade-out
    property bool gameLaunching: false    // lanzando cartridges/steam
    property bool gameArmed: false        // modo activo (Cartridges corriendo)

    function gameEnter() {
        gameModeService.gameShown = true;
        gameModeService.gameClosing = false;
        gameModeService.gameModeActive = true;
    }
    function gameCancel() {
        if (!gameModeService.gameModeActive) return;
        gameModeService.gameClosing = true;
        gameModeHide.restart();
    }
    function gameGo() {
        gameModeService.gameLaunching = true;
        gameLaunch.running = true;
    }
    function gameConfirmClose() {
        gameLaunch.command = ["game-mode.sh"];
        gameGo();
    }
    function gameConfirmNoClose() {
        gameLaunch.command = ["game-mode.sh", "noclose"];
        gameGo();
    }
    function gameExit() {
        gameExitProc.running = true;
        gameModeService.gameArmed = false;
        gameModeService.gameCancel();
    }
    function gameToggle() {
        if (gameModeService.gameModeActive) gameModeService.gameCancel();
        else gameModeService.gameEnter();
    }

    // Monitor de volante (botón PS, BTN_MODE): emite "1" → toglea modo juegos.
    Process {
        id: wheelMonitor
        command: ["wheel-mode-monitor.sh"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data === "1")
                    gameModeService.gameToggle();
            }
        }
    }

    Timer {
        id: gameModeHide
        interval: 240
        onTriggered: {
            gameModeService.gameModeActive = false;
            gameModeService.gameShown = false;
            gameModeService.gameClosing = false;
            gameModeService.gameLaunching = false;
        }
    }

    Process {
        id: gameLaunch
        command: ["true"]
        running: false
        onExited: {
            gameModeService.gameArmed = true;
            gameModeHide.restart();
        }
    }

    Process {
        id: gameExitProc
        command: ["game-mode.sh", "exit"]
        running: false
    }
}