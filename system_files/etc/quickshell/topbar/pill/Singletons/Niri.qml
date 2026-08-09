pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/fullscreen.js" as Fullscreen

/**
 * The single source of compositor truth for the pill. A persistent Process holds
 * an `event-stream` open (one line per serde/tagged JSON event, full snapshots
 * for workspaces/windows/outputs up-front); every event that lacks the full
 * windows/outputs picture triggers a one-shot re-query through a second socket
 * (a fresh `Process` per call, since the stream socket stops reading requests).
 * Everything the shell renders — dots, OSD, fullscreen heuristic — derives from
 * the state this singleton keeps.
 */
Singleton {
    id: root

    property var workspaces: []
    property var windows: []
    property var outputs: ({})

    signal stateChanged()

    readonly property string focusedMonitorName: {
        var ws = root.workspaces;
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].is_focused && ws[i].output)
                return ws[i].output;
        }
        return "";
    }

    function workspaceList(mon) {
        var out = [];
        var ws = root.workspaces;
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].output === mon) {
                out.push(ws[i]);
            }
        }
        out.sort(function (a, b) { return a.idx - b.idx; });
        return out;
    }

    function activeWorkspace(mon) {
        var ws = root.workspaces;
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].output === mon && ws[i].is_active)
                return ws[i];
        }
        return null;
    }

    /**
     * Reactive map monitor-name → "fullscreen real". Kept as a freshly-assigned
     * object so QML bindings that read `Niri.fullscreenByMonitor[mon]` re-evaluate;
     * `isFullscreen(mon)` below is only a non-reactive convenience getter.
     */
    property var fullscreenByMonitor: ({})

    function isFullscreen(mon) {
        return root.fullscreenByMonitor[mon] === true;
    }

    function recomputeFullscreen() {
        var next = {};
        var ws = root.workspaces;
        var activeId = {}; // output -> id do workspace ativo
        for (var i = 0; i < ws.length; i++) {
            if (ws[i].is_active && ws[i].output && ws[i].id !== undefined && ws[i].id !== null)
                activeId[ws[i].output] = ws[i].id;
        }
        var wins = root.windows;
        for (var j = 0; j < wins.length; j++) {
            var w = wins[j];
            if (w.workspace_id === undefined || w.workspace_id === null)
                continue;
            for (var mon in activeId) {
                if (activeId[mon] !== w.workspace_id)
                    continue;
                var out = root.outputs[mon];
                if (out && out.logical && Fullscreen.isFullscreenCovering(w.layout, out.logical))
                    next[mon] = true; // OR: uma janela que cobre = fullscreen; o mapa é rebuilt a cada call
            }
        }
        root.fullscreenByMonitor = next;
    }

    function applyStreamLine(line) {
        var obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        var key = Object.keys(obj)[0];
        if (!key)
            return;
        var payload = obj[key];
        if (key === "WorkspacesChanged") {
            root.workspaces = payload.workspaces;
            root.recomputeFullscreen();
            root.stateChanged();
        } else if (key === "WindowsChanged") {
            root.windows = payload.windows;
            root.recomputeFullscreen();
            root.stateChanged();
        } else if (key === "WindowOpenedOrChanged") {
            root.requeryWindows();
        } else if (key === "WindowClosed" || key === "WindowFocusChanged") {
            root.requeryWindows();
        } else if (key === "WindowLayoutsChanged") {
            root.requeryWindows();
        } else if (key === "WindowUrgencyChanged" || key === "WindowFocusTimestampChanged"
                   || key === "WorkspaceActivated" || key === "WorkspaceUrgencyChanged") {
            root.recomputeFullscreen();
            root.stateChanged();
        }
    }

    function requeryWindows() {
        windowsProc.command = ["niri", "msg", "--json", "windows"];
        windowsProc.running = true;
    }

    Component.onCompleted: {
        streamProc.running = true;
        outputsProc.running = true;
    }

    Process {
        id: outputsProc
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                if (!text.length)
                    return;
                try {
                    root.outputs = JSON.parse(text);
                } catch (e) { /* malformed */ }
            }
        }
    }

    Process {
        id: streamProc
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || !line.trim().length)
                    return;
                root.applyStreamLine(line);
            }
        }
    }

    Process {
        id: windowsProc
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                if (!text.length)
                    return;
                try {
                    root.windows = JSON.parse(text);
                    root.recomputeFullscreen();
                    root.stateChanged();
                } catch (e) { /* malformed */ }
            }
        }
    }

    function focusWorkspace(reference) {
        actionProc.command = ["niri", "msg", "action", "focus-workspace", String(reference)];
        actionProc.running = true;
    }

    function focusWindow(id) {
        actionProc.command = ["niri", "msg", "action", "focus-window", "--id", String(id)];
        actionProc.running = true;
    }

    function quit() {
        actionProc.command = ["niri", "msg", "action", "quit", "--skip-confirmation"];
        actionProc.running = true;
    }

    Process {
        id: actionProc
        command: ["niri", "msg", "action", "focus-workspace", "1"]
    }
}
