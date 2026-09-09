pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

Item {
    id: voiceService

    property bool handyRunning: false
    property bool loopActive: false
    property string lastTranscript: ""
    property int patternCount: 0

    // Check Handy dictation state.
    // Handy itself never exposes its recording state; the handy_toggle gesture
    // mirrors on/off to ~/.local/state/voice/handy-active, which we poll here.
    Process {
        id: handyCheck
        command: ["bash", "-c", "test -f \"$HOME/.local/state/voice/handy-active\" && echo 'running' || echo 'stopped'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                voiceService.handyRunning = this.text.trim() === "running";
            }
        }
    }

    // Check voice-loop status
    Process {
        id: loopCheck
        command: ["bash", "-c", "pgrep -f 'voice-loop.sh' >/dev/null && echo 'active' || echo 'inactive'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                voiceService.loopActive = this.text.trim() === "active";
            }
        }
    }

    // Read last transcript
    Process {
        id: transcriptRead
        command: ["bash", "-c", "cat ~/.local/state/voice/last-transcript.txt 2>/dev/null || echo ''"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t && t !== voiceService.lastTranscript) {
                    voiceService.lastTranscript = t;
                }
            }
        }
    }

    // Count patterns
    Process {
        id: patternCount
        command: ["bash", "-c", "jq '.commands | length' ~/.config/opencode/patterns.json 2>/dev/null || echo '0'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                voiceService.patternCount = parseInt(this.text.trim()) || 0;
            }
        }
    }

    // Poll timer
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            handyCheck.running = false;
            handyCheck.running = true;
            loopCheck.running = false;
            loopCheck.running = true;
            transcriptRead.running = false;
            transcriptRead.running = true;
        }
    }

    // Refresh patterns on startup
    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: {
            patternCount.running = false;
            patternCount.running = true;
        }
    }

    function refresh() {
        handyCheck.running = false;
        handyCheck.running = true;
        loopCheck.running = false;
        loopCheck.running = true;
        transcriptRead.running = false;
        transcriptRead.running = true;
        patternCount.running = false;
        patternCount.running = true;
    }

    function toggleLoop() {
        Qt.uiDelegate = "~/dotfiles/linux/bin/voice-loop.sh toggle";
    }
}